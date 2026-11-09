import '../../strength/data/progression_engine.dart';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import 'workout_seed.dart';
import 'personal_workout_seed.dart';
import 'workout_alternatives.dart';

const exerciseTypes = [
  'weighted',
  'bodyweight',
  'timedHold',
  'timedActivity',
  'distance',
];
const progressionModes = ['Progress', 'Maintain', 'Manual'];

class WorkoutRecord {
  final int id;
  final String kind;
  final int? parentId;
  final int position;
  final bool archived;
  final Map<String, dynamic> values;
  const WorkoutRecord(
    this.id,
    this.kind,
    this.parentId,
    this.position,
    this.archived,
    this.values,
  );
  String get name => values['name'] as String? ?? kind;
  factory WorkoutRecord.fromRow(QueryRow row) => WorkoutRecord(
    row.read<int>('id'),
    row.read<String>('kind'),
    row.readNullable<int>('parent_id'),
    row.read<int>('position'),
    row.read<int>('archived') != 0,
    Map<String, dynamic>.from(jsonDecode(row.read<String>('payload')) as Map),
  );
}

/// Calendar weeks start Monday. UTC dates avoid daylight-saving shifts.
int rotationIndex(DateTime date, DateTime anchor, int length, {int? override}) {
  if (length < 1) throw ArgumentError('A rotation needs at least one week');
  DateTime monday(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day - d.weekday + 1);
  final weeks = monday(date).difference(monday(anchor)).inDays ~/ 7;
  return (override ?? weeks) % length;
}

class WorkoutRepository {
  final AppDatabase db;
  WorkoutRepository(this.db);
  Future<List<WorkoutRecord>> list(
    String kind, {
    int? parentId,
    bool includeArchived = false,
  }) async {
    final rows = await db
        .customSelect(
          'SELECT * FROM management_records WHERE kind = ? ${parentId == null ? '' : 'AND parent_id = ?'} ${includeArchived ? '' : 'AND archived = 0'} ORDER BY position, id',
          variables: [
            Variable.withString(kind),
            if (parentId != null) Variable.withInt(parentId),
          ],
        )
        .get();
    return rows.map(WorkoutRecord.fromRow).toList();
  }

  Future<WorkoutRecord> get(int id) async => WorkoutRecord.fromRow(
    await db
        .customSelect(
          'SELECT * FROM management_records WHERE id = ?',
          variables: [Variable.withInt(id)],
        )
        .getSingle(),
  );

  void validate(String kind, Map<String, dynamic> values) {
    ProgressionEngine.validate(values);
    if (![
      'program',
      'workout',
      'exercise',
      'entry',
      'schedule',
      'preference',
    ].contains(kind)) {
      throw ArgumentError('Unknown record kind');
    }
    if (kind != 'schedule' &&
        (values['name'] as String? ?? '').trim().isEmpty) {
      throw ArgumentError('Name is required');
    }
    for (final key in [
      'sets',
      'reps',
      'repsMax',
      'restSeconds',
      'durationSeconds',
      'durationMaxSeconds',
      'distance',
      'load',
      'increment',
      'successCount',
      'deloadPercent',
    ]) {
      final value = values[key];
      if (value != null &&
          (value is! num ||
              !value.isFinite ||
              value < 0 ||
              (['sets', 'reps', 'repsMax', 'successCount'].contains(key) &&
                  (value < 1 || value != value.round())))) {
        throw ArgumentError('Invalid $key');
      }
    }
    for (final pair in [
      ('reps', 'repsMax'),
      ('durationSeconds', 'durationMaxSeconds'),
    ]) {
      if (values[pair.$1] is num &&
          values[pair.$2] is num &&
          (values[pair.$2] as num) < (values[pair.$1] as num)) {
        throw ArgumentError('Range maximum must not be below its target');
      }
    }
    if (values['type'] != null && !exerciseTypes.contains(values['type'])) {
      throw ArgumentError('Invalid exercise type');
    }
    if (values['progression'] != null &&
        !progressionModes.contains(values['progression'])) {
      throw ArgumentError('Invalid progression mode');
    }
    if (kind == 'program') {
      final cycle = values['cycle'];
      if (cycle is! List ||
          cycle.isEmpty ||
          cycle.any((v) => v is! String || v.trim().isEmpty)) {
        throw ArgumentError('Enter rotation week names');
      }
      DateTime.parse(values['anchor'] as String);
      final override = values['weekOverride'];
      if (override != null &&
          (override is! int || override < 0 || override >= cycle.length)) {
        throw ArgumentError('Invalid rotation override');
      }
    }
    if (kind == 'schedule') {
      final day = values['weekday'];
      final week = values['week'];
      if (day is! int ||
          day < 1 ||
          day > 7 ||
          (week != null && (week is! int || week < 0))) {
        throw ArgumentError('Invalid schedule day or week');
      }
    }
  }

  Future<int> create(
    String kind,
    Map<String, dynamic> values, {
    int? parentId,
  }) async {
    validate(kind, values);
    return db.transaction(() async {
      if (['workout', 'entry', 'schedule'].contains(kind) && parentId == null) {
        throw ArgumentError('A parent is required');
      }
      if (parentId != null) {
        final parent = await get(parentId);
        if ((kind == 'workout' || kind == 'schedule') &&
                parent.kind != 'program' ||
            kind == 'entry' && parent.kind != 'workout') {
          throw ArgumentError('Invalid parent');
        }
      }
      if (kind == 'entry') await _checkExercise(values);
      if (kind == 'schedule') await _checkSchedule(parentId!, values);
      final count = await db
          .customSelect(
            'SELECT COALESCE(MAX(position), -1) + 1 AS next FROM management_records WHERE kind = ? AND parent_id IS ?',
            variables: [Variable.withString(kind), Variable<int>(parentId)],
          )
          .getSingle();
      return db.customInsert(
        'INSERT INTO management_records(kind,parent_id,position,payload) VALUES (?,?,?,?)',
        variables: [
          Variable.withString(kind),
          Variable<int>(parentId),
          Variable.withInt(count.read<int>('next')),
          Variable.withString(jsonEncode(values)),
        ],
      );
    });
  }

  Future<void> _checkExercise(Map<String, dynamic> values) async {
    final exercise = await get(values['exerciseId'] as int);
    if (exercise.kind != 'exercise') throw ArgumentError('Choose an exercise');
    final alternatives = values['alternatives'] as List?;
    if (alternatives != null) {
      for (final option in alternatives) {
        final data = Map<String, dynamic>.from(option as Map);
        validate('entry', data);
        if ((await get(data['exerciseId'] as int)).kind != 'exercise') {
          throw ArgumentError('Choose an exercise for each alternative');
        }
      }
    }
  }

  Future<void> _checkSchedule(
    int programId,
    Map<String, dynamic> values,
  ) async {
    final program = await get(programId);
    final week = values['week'] as int?;
    if (week != null && week >= (program.values['cycle'] as List).length) {
      throw ArgumentError('Week is outside the program rotation');
    }
    if (values['workoutId'] != null) {
      final workout = await get(values['workoutId'] as int);
      if (workout.kind != 'workout' || workout.parentId != programId) {
        throw ArgumentError('Choose a workout in this program');
      }
    }
  }

  Future<void> edit(int id, Map<String, dynamic> values) async {
    final record = await get(id);
    if (record.kind == 'entry') values = saveSelectedAlternative(values);
    validate(record.kind, values);
    if (record.kind == 'entry') await _checkExercise(values);
    if (record.kind == 'schedule') {
      await _checkSchedule(record.parentId!, values);
    }
    if (record.kind == 'program') {
      final rules = await list('schedule', parentId: id, includeArchived: true);
      if (rules.any(
        (r) =>
            r.values['week'] != null &&
            r.values['week'] >= (values['cycle'] as List).length,
      )) {
        throw ArgumentError(
          'Reassign schedule weeks before shortening the rotation',
        );
      }
    }
    // Explicit prescription edits reset future targets; unrelated edits retain them.
    if (record.kind == 'exercise') {
      if (ProgressionEngine.signature(record.values) ==
          ProgressionEngine.signature(values)) {
        values = {
          ...values,
          if (record.values['progressionState'] != null)
            'progressionState': record.values['progressionState'],
        };
      } else {
        values = {...values}..remove('progressionState');
      }
    }
    await db.customStatement(
      'UPDATE management_records SET payload = ? WHERE id = ?',
      [jsonEncode(values), id],
    );
  }

  Future<void> archive(int id, bool archived) => db.customStatement(
    'UPDATE management_records SET archived = ? WHERE id = ?',
    [archived ? 1 : 0, id],
  );
  Future<void> reorder(String kind, int? parentId, List<int> ids) =>
      db.transaction(() async {
        final records = await list(kind, parentId: parentId);
        if (ids.toSet().length != ids.length ||
            records.length != ids.length ||
            !records.every((r) => ids.contains(r.id))) {
          throw ArgumentError(
            'Reorder must contain every active record exactly once',
          );
        }
        for (var i = 0; i < ids.length; i++) {
          await db.customStatement(
            'UPDATE management_records SET position = ? WHERE id = ?',
            [i, ids[i]],
          );
        }
      });
  Future<Map<String, dynamic>> resolvedEntry(
    WorkoutRecord entry, {
    int? alternative,
  }) async {
    final entryValues = alternative == null
        ? entry.values
        : selectWorkoutAlternative(entry.values, alternative);
    final workout = await get(entry.parentId!);
    final program = await get(workout.parentId!);
    final exercise = await get(entryValues['exerciseId'] as int);
    final resolved = <String, dynamic>{
      ...program.values,
      ...exercise.values,
      ...entryValues,
      'exerciseName': entryValues['displayName'] ?? exercise.name,
    };
    resolved.remove('alternatives');
    if ((resolved['type'] as String? ?? '').startsWith('timed') ||
        resolved['type'] == 'distance' ||
        resolved['repsUnknown'] == true) {
      resolved.remove('reps');
    }
    final signature = ProgressionEngine.signature(resolved);
    resolved.remove('progressionState');
    final state =
        (exercise.values['progressionState'] as Map?)?[signature] as Map?;
    resolved['progressionKey'] = signature;
    if (state?['load'] != null) resolved['load'] = state!['load'];
    return resolved;
  }

  /// Captures all names and targets by value; later edits cannot change history.
  Future<int> snapshot(
    int workoutId,
    DateTime completedAt, {
    List<Map<String, dynamic>> actualSets = const [],
  }) => db.transaction(() async {
    final workout = await get(workoutId);
    final entries = await list('entry', parentId: workoutId);
    final payload = {
      'workoutId': workout.id,
      'programId': workout.parentId,
      'workout': workout.values,
      'entries': await Future.wait(entries.map(resolvedEntry)),
      'actualSets': actualSets,
    };
    return db.customInsert(
      'INSERT INTO completed_snapshots(completed_at,payload) VALUES (?,?)',
      variables: [
        Variable.withString(completedAt.toIso8601String()),
        Variable.withString(jsonEncode(payload)),
      ],
    );
  });
  Future<List<WorkoutRecord>> scheduleFor(int programId, DateTime date) async {
    final p = await get(programId);
    final cycle = (p.values['cycle'] as List).cast<String>();
    final index = rotationIndex(
      date,
      DateTime.parse(p.values['anchor'] as String),
      cycle.length,
      override: p.values['weekOverride'] as int?,
    );
    if (p.archived) return [];
    final rules = (await list('schedule', parentId: programId))
        .where(
          (r) =>
              r.values['weekday'] == date.weekday &&
              (r.values['week'] == null || r.values['week'] == index),
        )
        .toList();
    final result = <WorkoutRecord>[];
    for (final rule in rules) {
      if (rule.values['workoutId'] == null) {
        result.add(rule);
      } else {
        final workout = await get(rule.values['workoutId'] as int);
        if (!workout.archived) {
          result.add(
            WorkoutRecord(
              rule.id,
              rule.kind,
              rule.parentId,
              rule.position,
              rule.archived,
              {...rule.values, 'name': workout.name},
            ),
          );
        }
      }
    }
    return result;
  }

  Future<void> seed() => db.transaction(() async {
    // Including archives prevents reseeding after a user archives the starter program.
    if ((await list('program', includeArchived: true)).isNotEmpty) return;
    await seedWorkouts(this);
  });

  Future<void> initialize() async {
    await seed();
    await seedPersonalWorkouts(this);
  }

  /// Copy templates into a program without changing its schedule or rotation.
  Future<int> copyWorkoutToProgram(int workoutId, int programId) =>
      db.transaction(() async {
        final source = await get(workoutId);
        if (source.kind != 'workout' || source.archived) {
          throw ArgumentError('Choose an active workout');
        }
        final destination = await get(programId);
        if (destination.kind != 'program' || destination.archived) {
          throw ArgumentError('Choose an active program');
        }
        final id = await create('workout', {
          ...source.values,
        }, parentId: programId);
        for (final entry in await list('entry', parentId: source.id)) {
          await create('entry', {...entry.values}, parentId: id);
        }
        return id;
      });
}

final workoutRepositoryProvider = Provider(
  (ref) => WorkoutRepository(ref.watch(databaseProvider)),
);
final managementRevisionProvider = NotifierProvider<ManagementRevision, int>(
  ManagementRevision.new,
);

class ManagementRevision extends Notifier<int> {
  @override
  int build() => 0;
  void refresh() => state++;
}

final managementReadyProvider = FutureProvider(
  (ref) => ref.watch(workoutRepositoryProvider).initialize(),
);
