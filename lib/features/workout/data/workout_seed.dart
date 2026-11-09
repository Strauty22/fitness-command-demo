import 'workout_repository.dart';

Future<void> seedWorkouts(WorkoutRepository repo) async {
  final program = await repo.create('program', {
    'name': 'Starter strength',
    'sets': 2,
    'reps': 10,
    'cycle': ['Week A', 'Week B'],
    'anchor': '2026-10-19',
    'restSeconds': 90,
  });
  final identities = <String, int>{};
  final rows = [
    [
      'Jump rope|timedActivity|300',
      'Pull-ups|bodyweight||4',
      'Goblet squat|weighted|10',
      'Chest press|weighted',
      'Seated row|weighted|110',
      'Back extension|bodyweight',
      'Shoulder press|weighted|70',
      'Lat pulldown|weighted|60',
      'Farmer carry|timedActivity|30',
      'Pallof press|weighted|50',
      'Face pull|weighted|50|12',
      'Leg curl|weighted|10',
      'Single-leg stand|timedHold|30',
    ],
    [
      'Full-body athletic warmup|timedActivity|300',
      'Negative pull-ups|bodyweight',
      'Bodyweight squat|bodyweight',
      'Lat pulldown|weighted|60',
      'Push-ups|bodyweight',
      'DB Romanian deadlift|weighted|20',
      'Cable row|weighted|110',
      'Shoulder press|weighted|70',
      'Suitcase carry|timedActivity|30',
      'Cable chop|weighted|50',
      'Face pull|weighted|50|12',
      'Leg curl|weighted|10',
      'Single-leg RDL reach|timedHold|30',
    ],
    [
      'Full-body athletic warmup|timedActivity|300',
      'Pull-ups|bodyweight||4',
      'Bodyweight squat|bodyweight',
      'Bench press|weighted',
      'Cable row|weighted|90',
      'Machine deadlift|weighted|70',
      'Lateral raise|weighted|10',
      'Face pull|weighted|40',
      'Suitcase carry|timedActivity|30',
      'Hanging crunches|bodyweight||10',
      'Band pull-apart|bodyweight||12',
      'Arm curl|weighted|60',
      'Single-leg RDL reach|timedHold|30',
    ],
    [
      'Jump rope|timedActivity|300',
      'Chin-ups|bodyweight',
      'Goblet squat|weighted|10',
      'Chin-ups|bodyweight',
      'Chest press|weighted|70',
      'Back extension|bodyweight',
      'Seated row|weighted|50',
      'Triceps press|weighted|30',
      'Farmer carry|timedActivity|30',
      'Dead bug|bodyweight',
      'Band pull-apart|bodyweight||12',
      'Lateral raise|weighted|10',
      'Single-leg stand|timedHold|30',
    ],
  ];
  const names = ['Tuesday A', 'Thursday A', 'Tuesday B', 'Thursday B'];
  const categories = [
    'Warmup',
    'Fresh Pull',
    'Squat',
    'Primary',
    'Primary',
    'Hinge',
    'Secondary',
    'Secondary',
    'Carry',
    'Core/Rotation',
    'Posture',
    'Optional Finisher',
    'Optional Balance',
  ];
  for (var w = 0; w < rows.length; w++) {
    final workout = await repo.create('workout', {
      'name': names[w],
    }, parentId: program);
    await repo.create('schedule', {
      'weekday': w.isEven ? 2 : 4,
      'week': w ~/ 2,
      'workoutId': workout,
      'name': names[w],
    }, parentId: program);
    for (var i = 0; i < rows[w].length; i++) {
      final parts = rows[w][i].split('|');
      final name = parts[0];
      final type = parts[1];
      final exercise = identities[name] ??= await repo.create('exercise', {
        'name': name,
        'type': type,
        'progression': 'Manual',
      });
      final timed = type.startsWith('timed');
      final amount = parts.length > 2 ? num.tryParse(parts[2]) : null;
      final reps = parts.length > 3 ? int.tryParse(parts[3]) : null;
      final notes = <String>[
        if (type == 'weighted') 'Load units unconfirmed; verify before use.',
        if (w == 0 && i == 3 || w == 2 && i == 3)
          'Source shows 70 without option assignment; confirm load.',
        if (i == 1) 'Quality sets; reps unknown unless specified.',
        if (i == 8)
          'Grain bucket; 30–45 seconds${w.isOdd || w == 2 ? ' per side' : ''}.',
        if (i == 10) '12–15 reps.',
        if (i == 12) '30 seconds per side.',
        if (name == 'Band pull-apart') 'Band resistance.',
        if (name == 'Lateral raise') 'Load per dumbbell/arm; verify.',
        if (w == 3 && i == 3) 'Assistance unknown.',
      ];
      await repo.create('entry', {
        'name': name,
        'exerciseId': exercise,
        'category': categories[i],
        'warmup': i == 0,
        'optional': i >= 11,
        'repsUnknown': i == 1 && reps == null,
        if (timed) 'durationSeconds': amount,
        if (timed) 'sets': i == 0 ? 1 : 2,
        if (!timed && amount != null) 'load': amount,
        'reps': ?reps,
        'notes': notes.join(' '),
      }, parentId: workout);
    }
  }
  for (final item in {
    1: 'Bike ride',
    3: 'Bike ride',
    5: 'Basketball',
    6: 'Rest / optional',
    7: 'Rest',
  }.entries) {
    await repo.create('schedule', {
      'name': item.value,
      'weekday': item.key,
    }, parentId: program);
  }
}
