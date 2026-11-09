import 'dart:convert';
import 'package:flutter/services.dart';
import '../core/database/app_database.dart';
import '../features/workout/data/compact_workout_upgrade.dart';
import '../features/workout/data/custom_workout_repository.dart';
import '../features/workout/data/workout_alternatives.dart';
import '../features/workout/data/workout_repository.dart';

const workoutTemplatesAsset = 'assets/data/workout_templates.json';
const _importMarker = 'Demo JSON workout templates v1';

Future<void> loadDemoWorkoutTemplates(AppDatabase db) async {
  final source = await rootBundle.loadString(workoutTemplatesAsset);
  await applyDemoWorkoutTemplates(
    db,
    jsonDecode(source) as Map<String, dynamic>,
  );
}

/// Update templates once, without touching sessions, snapshots or ride history.
/// Exported database identifiers are never treated as local identifiers.
Future<void> applyDemoWorkoutTemplates(
  AppDatabase db,
  Map<String, dynamic> source,
) async {
  if (source['format'] != 'fitness-command-workouts' ||
      source['version'] != 1) {
    throw const FormatException('Unsupported workout template format');
  }
  final repo = WorkoutRepository(db);
  await db.transaction(() async {
    if ((await repo.list('preference')).any((p) => p.name == _importMarker)) {
      return;
    }
    final variants = await ensureCompactWorkouts(repo);
    final exercises = {
      for (final e in await repo.list('exercise'))
        normalizedExerciseName(e.name): e.id,
    };
    Future<Map<String, dynamic>> prescription(Map raw) async {
      final name = (raw['exerciseName'] ?? raw['name']) as String;
      final key = normalizedExerciseName(name);
      final id = exercises[key] ??= await repo.create('exercise', {
        'name': name,
        'type': raw['type'],
        'progression': raw['progression'] ?? 'Manual',
      });
      return {
        for (final field in [
          ...alternativeFields,
          'category',
          'warmup',
          'optional',
        ])
          if (raw.containsKey(field)) field: raw[field],
        'name': raw['name'] ?? name,
        'exerciseId': id,
      };
    }

    final exported = (source['workouts'] as List).cast<Map>();
    for (final workout in exported) {
      late final WorkoutRecord target;
      if (workout['customWorkout'] == true) {
        final programs = await repo.list('program');
        final programId =
            programs
                .where((p) => p.values['customWorkoutProgram'] == true)
                .firstOrNull
                ?.id ??
            await repo.create('program', {
              'name': 'Custom workouts',
              'customWorkoutProgram': true,
              'cycle': ['Week A', 'Week B'],
              'anchor': '2026-10-19',
              'sets': 2,
              'reps': 10,
              'restSeconds': 90,
            });
        target = await repo.get(
          await repo.create('workout', {
            'name': workout['name'],
            customWorkoutKey: true,
          }, parentId: programId),
        );
      } else {
        target = variants.singleWhere(
          (w) => w.values[compactVariantKey] == workout['variant'],
        );
        await repo.edit(target.id, {...target.values, 'name': workout['name']});
      }
      final old = await repo.list('entry', parentId: target.id);
      final entries = (workout['entries'] as List).cast<Map>().toList()
        ..sort(
          (a, b) => (a['position'] as int).compareTo(b['position'] as int),
        );
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final values = await prescription({
          ...entry['prescription'] as Map,
          ...?entry['overrides'] as Map?,
        });
        if (entry['alternatives'] case final List options) {
          values['alternatives'] = [
            for (final option in options) await prescription(option as Map),
          ];
          values['selectedAlternative'] = entry['selectedAlternative'] ?? 0;
        }
        final id = i < old.length
            ? old[i].id
            : await repo.create('entry', values, parentId: target.id);
        if (i < old.length) await repo.edit(id, values);
        await db.customStatement(
          'UPDATE management_records SET position = ? WHERE id = ?',
          [i, id],
        );
      }
      for (final removed in old.skip(entries.length)) {
        await repo.archive(removed.id, true);
      }
    }
    await repo.create('preference', {'name': _importMarker});
  });
}
