import 'workout_alternatives.dart';
import 'workout_repository.dart';

const personalPlanKey = 'personal-workout-plan-v1';

class _Option {
  final String name, type, notes;
  final num? load;
  const _Option(this.name, this.type, {this.load, this.notes = ''});
}

class _Row {
  final String category, notes;
  final _Option a;
  final _Option? b;
  final int sets;
  final int? reps, seconds, maxReps, maxSeconds;
  final bool quality;
  const _Row(
    this.category,
    this.a,
    this.b, {
    this.sets = 2,
    this.reps = 10,
    this.seconds,
    this.maxReps,
    this.maxSeconds,
    this.quality = false,
    this.notes = '',
  });
}

const _jump = _Option('Jump rope', 'timedActivity');
const _warm = _Option('Full-body athletic warmup', 'timedActivity');
const _goblet = _Option('Goblet squat', 'weighted', load: 10);
const _squat = _Option('Bodyweight squat', 'bodyweight', notes: 'NA / BW');
const _chest = _Option('Chest press', 'weighted', load: 70);
const _decline = _Option('Decline push-ups', 'bodyweight', notes: 'BW');
const _row = _Option('Seated row', 'weighted', load: 110);
const _cable = _Option('Cable row', 'weighted', load: 90);
const _back = _Option('Back extension', 'bodyweight', notes: 'BW');
const _deadlift = _Option('Machine deadlift', 'weighted', load: 70);
const _shoulder = _Option('Shoulder press', 'weighted', load: 70);
const _lateral = _Option(
  'Lateral raise',
  'weighted',
  load: 10,
  notes: 'Per dumbbell / arm',
);
const _lat = _Option('Lat pulldown', 'weighted', load: 60);
const _face = _Option('Face pull', 'weighted', load: 50);
const _band = _Option(
  'Band pull-apart',
  'bodyweight',
  notes: 'Band resistance; not a numerical load.',
);
const _farmer = _Option('Farmer carry', 'timedActivity', notes: 'Grain bucket');
const _suitcase = _Option(
  'Suitcase carry',
  'timedActivity',
  notes: 'Grain bucket',
);
const _pallof = _Option('Pallof press', 'weighted', load: 50);
const _chop = _Option('Cable chop', 'weighted', load: 50);
const _leg = _Option('Leg curl', 'weighted', load: 10);
const _stand = _Option('Single-leg stand', 'timedHold', notes: 'BW');
const _reach = _Option('Single-leg RDL reach', 'timedHold', notes: 'BW');

const _tuesday = [
  _Row('Warmup', _jump, _warm, sets: 1, reps: null, seconds: 300),
  _Row(
    'Fresh Pull',
    _Option('Pull-ups', 'bodyweight'),
    _Option('Pull-ups', 'bodyweight'),
    reps: null,
    quality: true,
    notes:
        '2 quality sets; previous/reference performance: 4 / 4 reps. No fixed rep target.',
  ),
  _Row('Squat', _goblet, _squat),
  _Row(
    'Primary Push',
    _chest,
    _decline,
    notes:
        'Spreadsheet starting load 70 applies to Chest press; Decline push-ups uses BW.',
  ),
  _Row('Primary Pull', _row, _cable),
  _Row('Hinge', _back, _deadlift),
  _Row('Secondary Push', _shoulder, _lateral),
  _Row('Secondary Pull', _lat, _Option('Face pull', 'weighted', load: 40)),
  _Row('Carry', _farmer, _suitcase, reps: null, seconds: 30, maxSeconds: 45),
  _Row('Obliques', _pallof, _chop),
  _Row(
    'Abs',
    _Option('Physio Ball Cable Roll Up', 'weighted', load: 10),
    _Option('Physio Ball Cable Roll Up', 'weighted', load: 10),
    sets: 3,
    reps: 5,
  ),
  _Row('Posture', _face, _band, reps: 12, maxReps: 15),
  _Row('Optional Finisher', _leg, _Option('Arm curl', 'weighted', load: 60)),
  _Row(
    'Optional Balance',
    _stand,
    _reach,
    reps: null,
    seconds: 30,
    notes: 'Per side',
  ),
];
const _thursday = [
  _Row('Warmup', _warm, _jump, sets: 1, reps: null, seconds: 300),
  _Row(
    'Fresh Pull',
    _Option('Negative pull-ups', 'bodyweight'),
    _Option('Chin-ups', 'bodyweight'),
    reps: null,
    quality: true,
    notes: '2 quality sets; reps not specified.',
  ),
  _Row('Squat', _squat, _goblet),
  _Row(
    'Primary Pull',
    _lat,
    _Option('Chin-ups', 'bodyweight', notes: 'Assistance not specified.'),
  ),
  _Row('Primary Push', _decline, _chest),
  _Row('Hinge', _Option('DB Romanian deadlift', 'weighted', load: 20), _back),
  _Row('Secondary Pull', _cable, _row),
  _Row(
    'Secondary Push',
    _shoulder,
    _Option('Triceps press', 'weighted', load: 30),
  ),
  _Row(
    'Carry',
    _suitcase,
    _farmer,
    reps: null,
    seconds: 30,
    maxSeconds: 45,
    notes: 'Per side',
  ),
  _Row('Obliques', _chop, _pallof),
  _Row(
    'Abs',
    _Option('Plank', 'timedHold', notes: 'BW'),
    _Option('Plank', 'timedHold', notes: 'BW'),
    reps: null,
    seconds: 30,
  ),
  _Row('Posture', _face, _band, reps: 12, maxReps: 15),
  _Row('Optional Finisher', _leg, _lateral),
  _Row(
    'Optional Balance',
    _reach,
    _stand,
    reps: null,
    seconds: 30,
    notes: 'Per side',
  ),
];
const _saturday = [
  _Row(
    'Warmup',
    _warm,
    null,
    sets: 1,
    reps: null,
    notes:
        'Duration and set count not specified; one editable warmup log provided.',
  ),
  _Row(
    'Squat',
    _Option('Loaded Squat', 'weighted', load: 120),
    null,
    sets: 3,
    reps: 5,
  ),
  _Row(
    'Push',
    _Option('Chest Press', 'weighted', load: 90),
    null,
    sets: 3,
    reps: 5,
  ),
  _Row(
    'Pull',
    _Option('Lat Pulldown', 'weighted', load: 90),
    null,
    sets: 3,
    reps: 5,
  ),
  _Row(
    'Hinge',
    _Option('Machine Deadlift', 'weighted', load: 100),
    null,
    sets: 3,
    reps: 5,
  ),
  _Row(
    'Pull',
    _Option('Rear Fly on Yoga Ball', 'weighted', load: 20),
    null,
    sets: 3,
    reps: 5,
  ),
  _Row(
    'Abs',
    _Option('Curl Ups', 'bodyweight', notes: 'BW'),
    null,
    sets: 3,
    reps: 5,
  ),
];

/// Additive, atomic import. The archived program retains the durable import key.
Future<void> seedPersonalWorkouts(
  WorkoutRepository repo,
) => repo.db.transaction(() async {
  if ((await repo.list(
    'program',
    includeArchived: true,
  )).any((p) => p.values['importKey'] == personalPlanKey)) {
    return;
  }
  final program = await repo.create('program', {
    'name': 'My workout plan',
    'cycle': ['Every week'],
    'anchor': '2026-11-02',
    'restSeconds': 90,
    'importKey': personalPlanKey,
    'notes':
        'Imported spreadsheet plan. A/B are exercise alternatives, not rotation weeks. No schedule rules were added.',
  });
  final identities = {
    for (final e in await repo.list('exercise')) e.name.toLowerCase(): e.id,
  };
  for (final plan in {
    'Tuesday': _tuesday,
    'Thursday': _thursday,
    'Saturday': _saturday,
  }.entries) {
    final workout = await repo.create('workout', {
      'name': plan.key,
      'notes': plan.key == 'Saturday'
          ? 'Heavy Strength'
          : 'Option A default; Option B selectable',
    }, parentId: program);
    for (final row in plan.value) {
      final options = <Map<String, dynamic>>[];
      for (final option in [row.a, if (row.b != null) row.b!]) {
        final exerciseId = identities[option.name.toLowerCase()] ??= await repo
            .create('exercise', {
              'name': option.name,
              'type': option.type,
              'progression': 'Manual',
            });
        options.add({
          'name': option.name,
          'displayName': option.name,
          'exerciseId': exerciseId,
          'type': option.type,
          'sets': row.sets,
          'reps': row.reps,
          'repsMax': row.maxReps,
          'repsUnknown': row.quality,
          'durationSeconds': row.seconds,
          'durationMaxSeconds': row.maxSeconds,
          'load': option.load,
          'loadUnit': null,
          'progression': 'Manual',
          'notes': [
            row.notes,
            option.notes,
            if (option.load != null)
              'Load units unconfirmed; original spreadsheet value, no conversion.',
          ].where((n) => n.isNotEmpty).join(' '),
        });
      }
      var values = <String, dynamic>{
        ...options.first,
        'category': row.category,
        'warmup': row.category == 'Warmup',
        'optional': row.category.startsWith('Optional'),
        if (options.length > 1) 'alternatives': options,
      };
      if (options.length > 1) values = selectWorkoutAlternative(values, 0);
      await repo.create('entry', values, parentId: workout);
    }
  }
});
