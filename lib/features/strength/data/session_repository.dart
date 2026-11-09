import 'progression_engine.dart';
import '../compact_prescription.dart';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../workout/data/workout_repository.dart';
import 'strength_session.dart';

class SessionRepository {
  final AppDatabase db;
  final WorkoutRepository workouts;
  final DateTime Function() now;
  SessionRepository(this.db, this.workouts, {DateTime Function()? clock})
    : now = clock ?? DateTime.now;

  Future<void> deleteHistory(int id) => db.transaction(() async {
    final session = await get(id);
    if (session.unfinished) {
      throw StateError('Discard the active workout first');
    }
    await db.customStatement('INSERT INTO history_edit_permission VALUES (?)', [
      id,
    ]);
    await db.customStatement(
      "DELETE FROM completed_snapshots WHERE json_extract(payload, '\$.sessionId') = ?",
      [id],
    );
    await db.customStatement('DELETE FROM strength_sessions WHERE id = ?', [
      id,
    ]);
    await db.customStatement(
      'DELETE FROM history_edit_permission WHERE session_id = ?',
      [id],
    );
  });

  Future<StrengthSession> editHistorySet(
    int id,
    int exerciseIndex,
    int setIndex,
    Map<String, dynamic> actual,
  ) => db.transaction(() async {
    _validateActual(actual);
    final session = await get(id);
    if (session.unfinished) throw StateError('Use active workout editing');
    await db.customStatement('INSERT INTO history_edit_permission VALUES (?)', [
      id,
    ]);
    final data = copyJson(session.data);
    final set =
        (_exercise(data, exerciseIndex)['actualSets'] as List)[setIndex] as Map;
    set.addAll(actual);
    await db.customStatement(
      'UPDATE strength_sessions SET payload = ? WHERE id = ?',
      [jsonEncode(data), id],
    );
    await db.customStatement(
      "UPDATE completed_snapshots SET payload = ? WHERE json_extract(payload, '\$.sessionId') = ?",
      [
        jsonEncode({'sessionId': id, ...data}),
        id,
      ],
    );
    await db.customStatement(
      'DELETE FROM history_edit_permission WHERE session_id = ?',
      [id],
    );
    return get(id);
  });

  Future<StrengthSession> saveNotes(int id, String notes) =>
      _change(id, (_, data) {
        data['notes'] = notes;
      });

  Future<StrengthSession> get(int id) async => StrengthSession.fromRow(
    await db
        .customSelect(
          'SELECT * FROM strength_sessions WHERE id = ?',
          variables: [Variable.withInt(id)],
        )
        .getSingle(),
  );
  Future<StrengthSession?> unfinished() async {
    final rows = await db
        .customSelect(
          "SELECT * FROM strength_sessions WHERE status IN ('active','paused') LIMIT 1",
        )
        .get();
    return rows.isEmpty ? null : StrengthSession.fromRow(rows.single);
  }

  Future<List<StrengthSession>> history() async =>
      (await db
              .customSelect(
                "SELECT * FROM strength_sessions WHERE status = 'completed' ORDER BY ended_at DESC, id DESC",
              )
              .get())
          .map(StrengthSession.fromRow)
          .toList();

  /// Replacement is atomic: failed validation cannot discard the old session.
  Future<StrengthSession> replaceUnfinished(
    int workoutId,
    int expectedSessionId,
  ) => db.transaction(() async {
    final current = await unfinished();
    if (current == null || current.id != expectedSessionId) {
      throw StateError('The active workout changed. Please try again.');
    }
    await finish(current.id, cancel: true);
    return start(workoutId);
  });

  Future<StrengthSession> start(int workoutId) => db.transaction(() async {
    final existing = await unfinished();
    if (existing != null) {
      throw StateError('Resume or finish the current workout first');
    }
    final workout = await workouts.get(workoutId);
    if (workout.kind != 'workout' || workout.archived) {
      throw ArgumentError('Choose an active workout');
    }
    final program = await workouts.get(workout.parentId!);
    if (program.archived) throw ArgumentError('Program is archived');
    final entries = await workouts.list('entry', parentId: workoutId);
    if (entries.isEmpty) {
      throw StateError('Add exercises to this workout before starting');
    }
    final exercises = <Map<String, dynamic>>[];
    final finishedHistory = await history();
    for (final entry in entries) {
      final target = await workouts.resolvedEntry(entry);
      Map<String, dynamic> frozen(Map<String, dynamic> configured) {
        final previous = _previousFrom(
          finishedHistory,
          configured['exerciseId'] as int,
        );
        final target = workingTarget(configured, previous);
        return {
          'entryId': entry.id,
          'exerciseId': target['exerciseId'],
          'name': target['exerciseName'],
          'target': target,
          'skipped': false,
          'actualSets': List.generate(
            (target['sets'] as num? ?? 1).toInt(),
            (_) => <String, dynamic>{'completed': false},
          ),
          'previous': previous,
        };
      }

      final exercise = frozen(target);
      final options = entry.values['alternatives'] as List?;
      if (options != null) {
        exercise['alternativeChoices'] = [
          for (var i = 0; i < options.length; i++)
            frozen(await workouts.resolvedEntry(entry, alternative: i)),
        ];
        exercise['selectedAlternative'] =
            entry.values['selectedAlternative'] ?? 0;
        exercise['alternativeStates'] = <String, dynamic>{};
      }
      exercises.add(exercise);
    }
    final data = {
      'workoutId': workoutId,
      'programId': workout.parentId,
      'workoutName': workout.name,
      if ((workout.values['notes'] as String? ?? '').isNotEmpty)
        'notes': workout.values['notes'],
      'exercises': exercises,
    };
    final id = await db.customInsert(
      "INSERT INTO strength_sessions(status,started_at,payload) VALUES ('active',?,?)",
      variables: [
        Variable.withString(now().toUtc().toIso8601String()),
        Variable.withString(jsonEncode(data)),
      ],
    );
    return get(id);
  });

  /// Previous completed actuals follow the canonical exercise, across templates.
  Future<Map<String, dynamic>?> previous(int exerciseId) async =>
      _previousFrom(await history(), exerciseId);

  Map<String, dynamic>? _previousFrom(
    List<StrengthSession> history,
    int exerciseId,
  ) {
    for (final session in history) {
      if (session.status != 'completed') continue;
      final sets = <Map<String, dynamic>>[];
      Map<String, dynamic>? target;
      for (final exercise in session.loggedExercises) {
        if (exercise['exerciseId'] != exerciseId) continue;
        target = Map<String, dynamic>.from(exercise['target'] as Map);
        sets.addAll(
          (exercise['actualSets'] as List)
              .where((s) => s['completed'] == true)
              .map(
                (s) => <String, dynamic>{
                  'type': target!['type'],
                  'loadUnit': target['loadUnit'],
                  'distanceUnit': target['distanceUnit'],
                  'reps': null,
                  'load': null,
                  'durationSeconds': null,
                  'distance': null,
                  ...Map<String, dynamic>.from(s as Map),
                },
              ),
        );
      }
      if (sets.isNotEmpty) {
        return {
          'date': session.endedAt!.toIso8601String(),
          'target': target,
          'sets': sets,
        };
      }
    }
    return null;
  }

  Future<StrengthSession> _change(
    int id,
    void Function(StrengthSession, Map<String, dynamic>) change, {
    String? status,
  }) => db.transaction(() async {
    final session = await get(id);
    if (!session.unfinished) {
      throw StateError('Finished sessions are read-only');
    }
    final data = copyJson(session.data);
    change(session, data);
    await db.customStatement(
      'UPDATE strength_sessions SET status = ?, payload = ? WHERE id = ?',
      [status ?? session.status, jsonEncode(data), id],
    );
    return get(id);
  });
  Map<String, dynamic> _exercise(Map<String, dynamic> data, int index) =>
      (data['exercises'] as List)[index] as Map<String, dynamic>;

  Future<StrengthSession> switchAlternative(int id, int index, int choice) =>
      _change(id, (_, data) {
        final exercise = _exercise(data, index);
        final choices = exercise['alternativeChoices'] as List?;
        if (choices == null || choice < 0 || choice >= choices.length) {
          throw ArgumentError('Choose an available alternative');
        }
        final selected = exercise['selectedAlternative'] as int;
        if (selected == choice) return;
        final states = Map<String, dynamic>.from(
          exercise['alternativeStates'] as Map,
        );
        final saved = Map<String, dynamic>.from(exercise)
          ..remove('alternativeChoices')
          ..remove('alternativeStates')
          ..remove('selectedAlternative');
        states['$selected'] = saved;
        final next = Map<String, dynamic>.from(
          (states['$choice'] ?? choices[choice]) as Map,
        );
        (data['exercises'] as List)[index] = {
          ...next,
          'selectedAlternative': choice,
          'alternativeChoices': choices,
          'alternativeStates': states,
        };
        data.remove('restUntil');
        data.remove('pausedRestSeconds');
      });

  /// Session prescriptions are editable without changing completed actuals or templates.
  Future<StrengthSession> editTargets(
    int id,
    int index,
    Map<String, dynamic> changes,
  ) async {
    const allowed = ['sets', 'reps', 'load', 'durationSeconds', 'distance'];
    if (changes.keys.any((k) => !allowed.contains(k))) {
      throw ArgumentError('Invalid target field');
    }
    for (final item in changes.entries) {
      final value = item.value;
      if (value != null &&
          (value is! num ||
              !value.isFinite ||
              value < 0 ||
              (item.key == 'sets' || item.key == 'reps') &&
                  (value < 1 || value != value.round()))) {
        throw ArgumentError('Invalid ${item.key}');
      }
    }
    if (changes.containsKey('sets') && changes['sets'] == null) {
      throw ArgumentError('Set count is required');
    }
    return _change(id, (_, data) {
      final exercise = _exercise(data, index);
      final target = exercise['target'] as Map<String, dynamic>;
      final sets = exercise['actualSets'] as List;
      final count = (changes['sets'] as num? ?? sets.length).toInt();
      if (count < sets.length &&
          sets
              .skip(count)
              .any(
                (s) =>
                    (s as Map).keys.any((k) => k != 'completed') ||
                    s['completed'] == true,
              )) {
        throw StateError('Cannot remove sets with recorded actuals');
      }
      while (sets.length > count) {
        sets.removeLast();
      }
      while (sets.length < count) {
        sets.add(<String, dynamic>{'completed': false});
      }
      if (changes.containsKey('reps') && changes['reps'] != target['reps']) {
        target.remove('repsMax');
      }
      if (changes.containsKey('durationSeconds') &&
          changes['durationSeconds'] != target['durationSeconds']) {
        target.remove('durationMaxSeconds');
      }
      target.addAll(changes);
      if (changes['reps'] != null) target['repsUnknown'] = false;
      // Session edits must not accidentally trigger automatic template progression.
      target.remove('progressionKey');
    });
  }

  Future<StrengthSession> editExerciseInfo(
    int id,
    int index, {
    required String name,
    required String mode,
    required String notes,
  }) {
    if (name.trim().isEmpty || !progressionModes.contains(mode)) {
      throw ArgumentError('Invalid exercise settings');
    }
    return _change(id, (_, data) {
      final exercise = _exercise(data, index);
      exercise['name'] = name.trim();
      final target = exercise['target'] as Map;
      target['notes'] = notes;
      target['progression'] = mode;
      target.remove('progressionKey');
    });
  }

  Future<StrengthSession> usePrevious(int id, int index) => _change(id, (
    _,
    data,
  ) {
    final exercise = _exercise(data, index);
    final previous = exercise['previous'] as Map?;
    if (previous == null) return;
    final target = exercise['target'] as Map;
    final previousTarget = previous['target'] as Map;
    if (target['type'] != previousTarget['type'] ||
        target['loadUnit'] != previousTarget['loadUnit'] ||
        target['distanceUnit'] != previousTarget['distanceUnit']) {
      throw StateError('Previous measurements use different units or types');
    }
    final previousSets = previous['sets'] as List;
    final sets = exercise['actualSets'] as List;
    for (var i = 0; i < sets.length && i < previousSets.length; i++) {
      final set = sets[i] as Map;
      if (set['completed'] == true || set.length > 1) continue;
      for (final key in ['reps', 'load', 'durationSeconds', 'distance']) {
        if (previousSets[i][key] != null) set[key] = previousSets[i][key];
      }
    }
  });

  void _validateActual(Map<String, dynamic> actual) {
    for (final entry in actual.entries) {
      if (![
        'reps',
        'load',
        'durationSeconds',
        'distance',
      ].contains(entry.key)) {
        throw ArgumentError('Invalid actual field');
      }
      final value = entry.value;
      if (value != null &&
          (value is! num ||
              !value.isFinite ||
              value < 0 ||
              entry.key == 'reps' && value != value.round())) {
        throw ArgumentError('Enter a non-negative ${entry.key}');
      }
    }
  }

  Future<StrengthSession> editSet(
    int id,
    int exerciseIndex,
    int setIndex,
    Map<String, dynamic> actual,
  ) {
    _validateActual(actual);
    return _change(id, (session, data) {
      final exercise = _exercise(data, exerciseIndex);
      final set =
          (exercise['actualSets'] as List)[setIndex] as Map<String, dynamic>;
      set.addAll(actual);
    });
  }

  Future<StrengthSession> completeSet(
    int id,
    int exerciseIndex,
    int setIndex,
  ) => _change(id, (session, data) {
    if (session.status != 'active') {
      throw StateError('Resume the workout before logging sets');
    }
    final exercise = _exercise(data, exerciseIndex);
    if (exercise['skipped'] == true) {
      throw StateError('Restore this exercise before logging');
    }
    final set =
        (exercise['actualSets'] as List)[setIndex] as Map<String, dynamic>;
    if (set['completed'] == true) {
      return; // Repeated taps never restart the timer.
    }
    final target = exercise['target'] as Map<String, dynamic>;
    for (final key in ['reps', 'load', 'durationSeconds', 'distance']) {
      if (!set.containsKey(key) && target[key] != null) set[key] = target[key];
    }
    if (set['load'] != null && !set.containsKey('loadUnit')) {
      set['loadUnit'] = displayLoadUnit(target);
    }
    set['completed'] = true;
    set['completedAt'] = now().toUtc().toIso8601String();
    final seconds =
        (data['restSeconds'] as int?) ??
        (target['restSeconds'] as num?)?.toInt() ??
        90;
    if (seconds == 0) {
      data.remove('restUntil');
    } else {
      data['restUntil'] = now()
          .toUtc()
          .add(Duration(seconds: seconds))
          .toIso8601String();
    }
  });

  /// Read the latest actual inside a transaction so repeated taps never use stale reps.
  Future<StrengthSession> tapSet(int id, int exerciseIndex, int setIndex) =>
      db.transaction(() async {
        final session = await get(id);
        if (session.status != 'active') {
          throw StateError('Resume the workout before logging sets');
        }
        final exercise = session.exercises[exerciseIndex];
        if (exercise['skipped'] == true) {
          throw StateError('Restore this exercise before logging');
        }
        final set = (exercise['actualSets'] as List)[setIndex] as Map;
        if (set['completed'] != true) {
          return completeSet(id, exerciseIndex, setIndex);
        }
        final type = exercise['target']['type'] as String? ?? 'weighted';
        if (type.startsWith('timed') ||
            type == 'distance' ||
            set['reps'] is! num) {
          return undoSet(id, exerciseIndex, setIndex);
        }
        return _change(id, (_, data) {
          final actual =
              (_exercise(data, exerciseIndex)['actualSets'] as List)[setIndex]
                  as Map;
          final reps = (actual['reps'] as num).toInt();
          if (reps <= 0) {
            actual
              ..clear()
              ..['completed'] = false;
            data.remove('restUntil');
            data.remove('pausedRestSeconds');
          } else {
            actual['reps'] = reps - 1;
          }
        });
      });

  Future<StrengthSession> undoSet(int id, int exerciseIndex, int setIndex) =>
      _change(id, (_, data) {
        final set =
            (_exercise(data, exerciseIndex)['actualSets'] as List)[setIndex]
                as Map<String, dynamic>;
        set['completed'] = false;
        set.remove('completedAt');
        data.remove('restUntil');
        data.remove('pausedRestSeconds');
      });
  Future<StrengthSession> skip(int id, int exerciseIndex, bool skipped) =>
      _change(id, (_, data) {
        // Preserve actuals already recorded when skipping the remaining sets.
        _exercise(data, exerciseIndex)['skipped'] = skipped;
      });
  Future<StrengthSession> configureRest(int id, int? seconds) {
    if (seconds != null && (seconds < 0 || seconds > 3600)) {
      throw ArgumentError('Rest must be 0–3600 seconds');
    }
    return _change(id, (_, data) {
      if (seconds == null) {
        data.remove('restSeconds');
      } else {
        data['restSeconds'] = seconds;
      }
    });
  }

  Future<StrengthSession> stopRest(int id) => _change(id, (_, data) {
    data.remove('restUntil');
    data.remove('pausedRestSeconds');
  });
  Future<StrengthSession> pause(int id) => _change(id, (session, data) {
    data['pausedRestSeconds'] = session.restRemaining(now());
    data.remove('restUntil');
  }, status: 'paused');
  Future<StrengthSession> resume(int id) => _change(id, (session, data) {
    if (session.status != 'paused') return;
    data['restUntil'] = now()
        .toUtc()
        .add(Duration(seconds: data['pausedRestSeconds'] as int? ?? 0))
        .toIso8601String();
    data.remove('pausedRestSeconds');
  }, status: 'active');

  Future<StrengthSession> finish(
    int id, {
    bool cancel = false,
  }) => db.transaction(() async {
    final session = await get(id);
    if (!session.unfinished) return session; // Safe repeated finish.
    final ended = now().toUtc().toIso8601String();
    final data = copyJson(session.data)
      ..remove('restUntil')
      ..remove('pausedRestSeconds');
    if (!cancel) {
      // Completion and future targets commit atomically; repeated finish is safe.
      final processed = <String>{};
      for (final logged in session.loggedExercises) {
        final target = Map<String, dynamic>.from(logged['target'] as Map);
        final key = target['progressionKey'] as String?;
        if (key == null) continue;
        final exerciseId = logged['exerciseId'] as int;
        if (!processed.add('$exerciseId:$key')) continue;
        final entry = await workouts.get(logged['entryId'] as int);
        final current = await workouts.resolvedEntry(
          entry,
          alternative: logged['selectedAlternative'] as int?,
        );
        // A target/settings edit made during this session takes precedence.
        if (current['progressionKey'] != key ||
            current['load'] != target['load'] ||
            current['progression'] != target['progression']) {
          continue;
        }
        final exercise = await workouts.get(exerciseId);
        final states = Map<String, dynamic>.from(
          exercise.values['progressionState'] as Map? ?? {},
        );
        final old = Map<String, dynamic>.from(states[key] as Map? ?? {});
        final next = ProgressionEngine.evaluate(
          target,
          (logged['actualSets'] as List)
              .map((s) => Map<String, dynamic>.from(s as Map))
              .toList(),
          old,
          skipped: logged['skipped'] == true,
        );
        if (jsonEncode(next) != jsonEncode(old)) {
          states[key] = next;
          await db.customStatement(
            'UPDATE management_records SET payload = ? WHERE id = ?',
            [
              jsonEncode({...exercise.values, 'progressionState': states}),
              exerciseId,
            ],
          );
        }
      }
      // Use the frozen session, never reread edited templates to make history.
      await db.customInsert(
        'INSERT INTO completed_snapshots(completed_at,payload) VALUES (?,?)',
        variables: [
          Variable.withString(ended),
          Variable.withString(jsonEncode({'sessionId': id, ...data})),
        ],
      );
    }
    await db.customStatement(
      'UPDATE strength_sessions SET status = ?, ended_at = ?, payload = ? WHERE id = ?',
      [cancel ? 'cancelled' : 'completed', ended, jsonEncode(data), id],
    );
    return get(id);
  });
}

final sessionRepositoryProvider = Provider(
  (ref) => SessionRepository(
    ref.watch(databaseProvider),
    ref.watch(workoutRepositoryProvider),
  ),
);
final sessionRevisionProvider = NotifierProvider<SessionRevision, int>(
  SessionRevision.new,
);

class SessionRevision extends Notifier<int> {
  @override
  int build() => 0;
  void refresh() => state++;
}

final unfinishedSessionProvider = FutureProvider((ref) {
  ref.watch(sessionRevisionProvider);
  return ref.watch(sessionRepositoryProvider).unfinished();
});
final sessionProvider = FutureProvider.family<StrengthSession, int>((ref, id) {
  ref.watch(sessionRevisionProvider);
  return ref.watch(sessionRepositoryProvider).get(id);
});
final sessionHistoryProvider = FutureProvider((ref) {
  ref.watch(sessionRevisionProvider);
  return ref.watch(sessionRepositoryProvider).history();
});
