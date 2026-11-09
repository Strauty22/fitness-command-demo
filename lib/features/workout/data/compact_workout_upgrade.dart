import 'personal_workout_seed.dart';
import 'workout_repository.dart';
import 'workout_alternatives.dart';

const compactVariantKey = 'compactVariant';
const compactVariantNames = [
  'Tuesday A',
  'Tuesday B',
  'Thursday A',
  'Thursday B',
  'Saturday A',
  'Saturday B',
];

/// Additive, idempotent upgrade. No historical payloads or exercise identities change.
Future<List<WorkoutRecord>> ensureCompactWorkouts(
  WorkoutRepository repo,
) => repo.db.transaction(() async {
  await repo.initialize();
  final programs = await repo.list('program', includeArchived: true);
  final imported = programs
      .where((p) => p.values['importKey'] == personalPlanKey)
      .firstOrNull;
  if (imported == null || imported.archived) return <WorkoutRecord>[];
  final all = await repo.list(
    'workout',
    parentId: imported.id,
    includeArchived: true,
  );
  final markers = await repo.list('preference');
  const unitKey = 'Imported pounds confirmed v1';
  if (!markers.any((p) => p.name == unitKey)) {
    for (final workout in all) {
      for (final entry in await repo.list(
        'entry',
        parentId: workout.id,
        includeArchived: true,
      )) {
        Map<String, dynamic> pounds(Map<String, dynamic> original) {
          final next = Map<String, dynamic>.from(original);
          if ((next['loadUnit'] as String? ?? '').trim().isEmpty) {
            next['loadUnit'] = 'lb';
          }
          final notes = next['notes'] as String?;
          if (notes != null) {
            next['notes'] = notes
                .replaceAll(
                  'Load units unconfirmed; original spreadsheet value, no conversion.',
                  '',
                )
                .trim();
          }
          return next;
        }

        final values = pounds(entry.values);
        if (values['alternatives'] is List) {
          values['alternatives'] = [
            for (final option in values['alternatives'] as List)
              pounds(Map<String, dynamic>.from(option as Map)),
          ];
        }
        await repo.edit(entry.id, values);
      }
    }
    await repo.create('preference', {'name': unitKey});
  }
  for (final name in compactVariantNames) {
    if (all.any((w) => w.values[compactVariantKey] == name)) continue;
    final day = name.split(' ').first;
    final source = all
        .where((w) => w.name == day && w.values[compactVariantKey] == null)
        .firstOrNull;
    if (source == null) continue;
    final option = name.endsWith('B') ? 1 : 0;
    final id = await repo.create('workout', {
      ...source.values,
      'name': name,
      compactVariantKey: name,
      'sourceWorkoutId': source.id,
    }, parentId: imported.id);
    for (final entry in await repo.list('entry', parentId: source.id)) {
      final alternatives = entry.values['alternatives'] as List?;
      final values = alternatives == null
          ? {...entry.values}
          : selectWorkoutAlternative(
              entry.values,
              option < alternatives.length ? option : 0,
            );
      await repo.create('entry', values, parentId: id);
    }
  }
  final variants = await repo.list('workout', parentId: imported.id);
  final selected = (await repo.list(
    'preference',
  )).where((p) => p.name == 'Selected workout').firstOrNull;
  if (selected != null &&
      !variants.any(
        (w) =>
            w.values[compactVariantKey] != null &&
            w.id == selected.values['workoutId'],
      )) {
    final previous = (await repo.list(
      'workout',
      includeArchived: true,
    )).where((w) => w.id == selected.values['workoutId']).firstOrNull;
    if (previous != null && previous.parentId == imported.id) {
      final name = compactVariantNames.contains(previous.name)
          ? previous.name
          : '${previous.name} A';
      final replacement = variants
          .where((w) => w.values[compactVariantKey] == name)
          .firstOrNull;
      if (replacement != null) {
        await repo.edit(selected.id, {
          ...selected.values,
          'workoutId': replacement.id,
        });
      }
    }
  }

  return [
    for (final name in compactVariantNames)
      ...variants.where((w) => w.values[compactVariantKey] == name),
  ];
});
