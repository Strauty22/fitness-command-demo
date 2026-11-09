import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/demo/sample_data.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';
import 'package:fitness_command/features/workout/data/compact_workout_upgrade.dart';
import 'package:fitness_command/features/strength/data/session_repository.dart';
import 'package:fitness_command/features/history/personal_bests.dart';
import 'package:fitness_command/features/cycling/platform/ride_platform.dart';
import 'package:fitness_command/features/cycling/data/ride_repository.dart';

void main() {
  test(
    'fictional seed has six variants, history and PBs, and seeds once',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await seedDemo(db);
      final workouts = WorkoutRepository(db);
      final variants = await ensureCompactWorkouts(workouts);
      expect(variants.map((w) => w.name), compactVariantNames);
      final sessions = SessionRepository(db, workouts);
      final history = await sessions.history();
      expect(history.length, 3);
      expect(exerciseBests(history), isNotEmpty);
      expect(await sessions.unfinished(), isNull);
      expect(await RideRepository(db).get('fictional-sample-ride'), isNotNull);
      await seedDemo(db);
      expect((await sessions.history()).length, 3);
      final active = await sessions.start(variants.first.id);
      await sessions.completeSet(active.id, 0, 0);
      expect((await sessions.get(active.id)).completedSets, 1);
      expect((await sessions.history()).length, 3);
    },
  );

  test(
    'simulated GPS supports start, pause, resume, finish and export',
    () async {
      final platform = SimulatedRidePlatform();
      addTearDown(platform.dispose);
      final start = await platform.command('start');
      platform.tick();
      final afterTick = await platform.current();
      expect(afterTick!['acceptedPoints'], 1);
      await platform.command('pause');
      platform.tick();
      expect((await platform.current())!['acceptedPoints'], 1);
      await platform.command('resume');
      platform.tick();
      await platform.command('review');
      await platform.command('save', notes: 'Fictional test ride');
      expect(await platform.current(), isNull);
      final exported = await platform.export(start['id'] as String, 0);
      expect((exported['points'] as List).length, 2);
      expect((exported['ride'] as Map)['status'], 'completed');
    },
  );
}
