import '../core/database/app_database.dart';
import '../features/workout/data/workout_repository.dart';
import '../features/workout/data/compact_workout_upgrade.dart';
import '../features/strength/data/session_repository.dart';
import '../features/cycling/data/ride.dart';
import '../features/cycling/data/ride_repository.dart';

/// Only code-defined fictional records enter this isolated demo database.
Future<void> seedDemo(AppDatabase db) async {
  final workouts = WorkoutRepository(db);
  await db.transaction(() async {
    if ((await workouts.list(
      'preference',
    )).any((p) => p.name == 'Fictional demo sample v1')) {
      return;
    }
    final variants = await ensureCompactWorkouts(workouts);
    for (var week = 0; week < 3; week++) {
      var clock = DateTime.utc(2026, 10, 13 + week * 7, 17);
      final sessions = SessionRepository(db, workouts, clock: () => clock);
      final session = await sessions.start(variants.first.id);
      for (var e = 0; e < session.exercises.length; e++) {
        final exercise = session.exercises[e];
        final target = exercise['target'] as Map;
        for (var s = 0; s < (exercise['actualSets'] as List).length; s++) {
          if (target['load'] is num) {
            await sessions.editSet(session.id, e, s, {
              'load': (target['load'] as num) + week * 2.5,
            });
          }
          await sessions.completeSet(session.id, e, s);
          clock = clock.add(const Duration(minutes: 2));
        }
      }
      await sessions.saveNotes(session.id, 'Fictional demo workout');
      await sessions.finish(session.id);
    }
    final started = DateTime.utc(2026, 10, 28, 16);
    final points = List.generate(
      40,
      (i) => RidePoint(
        sequence: i + 1,
        segment: 0,
        time: started.add(Duration(seconds: i * 60)),
        latitude: 0.02 + i * 0.0001,
        longitude: 0.02 + i * 0.00015,
        accuracy: 3,
        altitude: 20 + i / 2,
        speed: 5,
      ),
    );
    await RideRepository(db).importCapture(
      Ride({
        'id': 'fictional-sample-ride',
        'status': 'completed',
        'startedAt': started.millisecondsSinceEpoch,
        'endedAt': started
            .add(const Duration(minutes: 40))
            .millisecondsSinceEpoch,
        'activeMillis': 2400000,
        'movingMillis': 2400000,
        'acceptedPoints': points.length,
        'lastSequence': points.length,
        'distanceMetres': 12000,
        'elevationGain': 20,
        'maximumSpeed': 7,
        'updatedAt': 1,
        'notes': 'Fictional demo ride; synthetic route and statistics.',
      }),
      points,
    );
    await RideRepository(db).annotate(
      'fictional-sample-ride',
      personalBest: true,
      name: 'Fictional riverside loop',
    );
    await workouts.create('preference', {'name': 'Fictional demo sample v1'});
  });
}
