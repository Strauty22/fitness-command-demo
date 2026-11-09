// Each alternative keeps a distinct exercise identity and prescription.
const alternativeFields = [
  'name',
  'displayName',
  'exerciseId',
  'type',
  'sets',
  'reps',
  'repsMax',
  'durationSeconds',
  'durationMaxSeconds',
  'distance',
  'distanceUnit',
  'load',
  'loadUnit',
  'repsUnknown',
  'notes',
  'progression',
  'increment',
  'successCount',
  'failureCount',
  'allowedFailedSets',
  'deloadPercent',
  'restSeconds',
];

Map<String, dynamic> selectWorkoutAlternative(
  Map<String, dynamic> values,
  int index,
) {
  final options = values['alternatives'] as List?;
  if (options == null || index < 0 || index >= options.length) {
    throw ArgumentError('Choose an available alternative');
  }
  final next = Map<String, dynamic>.from(values);
  for (final key in alternativeFields) {
    next.remove(key);
  }
  return {
    ...next,
    ...Map<String, dynamic>.from(options[index] as Map),
    'selectedAlternative': index,
  };
}

Map<String, dynamic> saveSelectedAlternative(Map<String, dynamic> values) {
  final options = values['alternatives'] as List?;
  if (options == null) return values;
  final index = values['selectedAlternative'] as int? ?? 0;
  if (index < 0 || index >= options.length) {
    throw ArgumentError('Invalid alternative');
  }
  final updated = [
    for (final option in options) Map<String, dynamic>.from(option as Map),
  ];
  updated[index] = {
    for (final key in alternativeFields)
      if (values.containsKey(key)) key: values[key],
  };
  return {...values, 'alternatives': updated};
}
