import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show MigrationStrategy;
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late WorkoutRepository repo;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = WorkoutRepository(db);
  });
  tearDown(() => db.close());
  test(
    'seed is idempotent, separate entries share independent identities',
    () async {
      await repo.seed();
      await repo.seed();
      expect(await repo.list('program'), hasLength(1));
      final workouts = await repo.list('workout');
      expect(workouts.map((w) => w.name), [
        'Tuesday A',
        'Thursday A',
        'Tuesday B',
        'Thursday B',
      ]);
      for (final w in workouts) {
        expect(await repo.list('entry', parentId: w.id), hasLength(13));
      }
      final a = await repo.list('entry', parentId: workouts[0].id);
      final b = await repo.list('entry', parentId: workouts[2].id);
      expect(a[2].values['exerciseId'], isNot(b[2].values['exerciseId']));
      expect(a[1].values['exerciseId'], b[1].values['exerciseId']);
      expect(a.first.values['warmup'], true);
      expect(a.last.values['optional'], true);
      await repo.archive((await repo.list('program')).single.id, true);
      await repo.seed();
      expect(await repo.list('program'), isEmpty);
    },
  );
  test(
    'defaults, overrides, edits, reorder, archive and immutable history',
    () async {
      await repo.seed();
      final w = (await repo.list('workout')).first;
      final entries = await repo.list('entry', parentId: w.id);
      final e = entries[2];
      expect((await repo.resolvedEntry(e))['sets'], 2);
      await repo.edit(e.id, {
        ...e.values,
        'sets': 4,
        'reps': 8,
        'progression': 'Maintain',
        'load': 25,
      });
      expect((await repo.resolvedEntry(await repo.get(e.id)))['sets'], 4);
      final snapshotId = await repo.snapshot(w.id, DateTime(2026, 10, 20));
      final before = await db
          .customSelect(
            'SELECT payload FROM completed_snapshots WHERE id = $snapshotId',
          )
          .getSingle();
      await repo.edit(e.id, {...e.values, 'load': 999});
      final identity = await repo.get(e.values['exerciseId'] as int);
      await repo.edit(identity.id, {...identity.values, 'name': 'Renamed'});
      final after = await db
          .customSelect(
            'SELECT payload FROM completed_snapshots WHERE id = $snapshotId',
          )
          .getSingle();
      expect(after.read<String>('payload'), before.read<String>('payload'));
      expect(
        jsonDecode(after.read<String>('payload'))['entries'][2]['load'],
        25,
      );
      await expectLater(
        db.customStatement("UPDATE completed_snapshots SET payload = '{}'"),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement('DELETE FROM completed_snapshots'),
        throwsA(anything),
      );
      final ids = entries.map((e) => e.id).toList().reversed.toList();
      await repo.reorder('entry', w.id, ids);
      expect((await repo.list('entry', parentId: w.id)).map((e) => e.id), ids);
      await expectLater(
        repo.reorder('entry', w.id, [ids.first]),
        throwsArgumentError,
      );
      await repo.archive(e.id, true);
      expect(await repo.list('entry', parentId: w.id), hasLength(12));
      await repo.archive(e.id, false);
      expect(await repo.list('entry', parentId: w.id), hasLength(13));
    },
  );
  test(
    'calendar rotation is weekly, supports prior dates, cycles and override',
    () {
      final anchor = DateTime(2026, 10, 19);
      for (var day = 19; day <= 25; day++) {
        expect(rotationIndex(DateTime(2026, 10, day), anchor, 2), 0);
      }
      expect(rotationIndex(DateTime(2026, 10, 26), anchor, 2), 1);
      expect(rotationIndex(DateTime(2026, 10, 18), anchor, 2), 1);
      expect(rotationIndex(DateTime(2026, 11, 2), anchor, 3), 2);
      expect(rotationIndex(DateTime(2026, 11, 9), anchor, 3), 0);
      expect(rotationIndex(DateTime(2026, 11, 9), anchor, 3, override: 2), 2);
      expect(() => rotationIndex(anchor, anchor, 0), throwsArgumentError);
    },
  );
  test('rotation crosses month, year and leap day in whole calendar weeks', () {
    final anchor = DateTime(2026, 12, 31); // Thursday in Week A.
    expect(rotationIndex(DateTime(2027, 1, 3), anchor, 2), 0);
    expect(rotationIndex(DateTime(2027, 1, 4), anchor, 2), 1);
    expect(rotationIndex(DateTime(2027, 1, 11), anchor, 2), 0);
    expect(rotationIndex(DateTime(2026, 12, 27), anchor, 2), 1);
    expect(rotationIndex(DateTime(2026, 12, 20), anchor, 3), 1);
    expect(rotationIndex(DateTime(2028, 3, 5), DateTime(2028, 2, 29), 2), 0);
    expect(rotationIndex(DateTime(2028, 3, 6), DateTime(2028, 2, 29), 2), 1);
  });
  test('schedule follows calendar and manual override', () async {
    await repo.seed();
    final p = (await repo.list('program')).single;
    expect(
      (await repo.scheduleFor(p.id, DateTime(2026, 10, 20))).single.name,
      'Tuesday A',
    );
    expect(
      (await repo.scheduleFor(p.id, DateTime(2026, 10, 27))).single.name,
      'Tuesday B',
    );
    await repo.edit(p.id, {...p.values, 'weekOverride': 1});
    expect(
      (await repo.scheduleFor(p.id, DateTime(2026, 10, 22))).single.name,
      'Thursday B',
    );
  });
  test(
    'removing override restores original schedule without moving anchor',
    () async {
      await repo.seed();
      final p = (await repo.list('program')).single;
      final original = jsonEncode(p.values);
      await repo.edit(p.id, {...p.values, 'weekOverride': 1});
      expect(
        (await repo.scheduleFor(p.id, DateTime(2026, 10, 20))).single.name,
        'Tuesday B',
      );
      expect((await repo.get(p.id)).values['anchor'], p.values['anchor']);
      final automatic = {...(await repo.get(p.id)).values}
        ..remove('weekOverride');
      await repo.edit(p.id, automatic);
      expect(jsonEncode((await repo.get(p.id)).values), original);
      expect(
        (await repo.scheduleFor(p.id, DateTime(2026, 10, 20))).single.name,
        'Tuesday A',
      );
      expect(
        (await repo.scheduleFor(p.id, DateTime(2026, 10, 27))).single.name,
        'Tuesday B',
      );
    },
  );
  test('invalid targets rejected, all measurement types persist', () async {
    for (final type in exerciseTypes) {
      final id = await repo.create('exercise', {
        'name': type,
        'type': type,
        'progression': 'Progress',
        'durationSeconds': 30,
        'distance': 5,
      });
      expect((await repo.get(id)).values['type'], type);
    }
    await expectLater(
      repo.create('exercise', {'name': 'Bad', 'sets': -1}),
      throwsArgumentError,
    );
    await expectLater(
      repo.create('program', {'name': 'Bad', 'cycle': []}),
      throwsArgumentError,
    );
  });
  test('management edits persist across reopening file', () async {
    final dir = await Directory.systemTemp.createTemp('workout_persistence');
    final file = File('${dir.path}/app.sqlite');
    final first = AppDatabase.forTesting(NativeDatabase(file));
    final r = WorkoutRepository(first);
    await r.seed();
    final p = (await r.list('program')).single;
    await r.edit(p.id, {
      ...p.values,
      'name': 'Edited program',
      'cycle': ['A', 'B', 'C'],
    });
    await first.close();
    final second = AppDatabase.forTesting(NativeDatabase(file));
    try {
      expect(
        (await WorkoutRepository(second).get(p.id)).name,
        'Edited program',
      );
      expect((await WorkoutRepository(second).get(p.id)).values['cycle'], [
        'A',
        'B',
        'C',
      ]);
    } finally {
      await second.close();
      await dir.delete(recursive: true);
    }
  });
  test('version 1 upgrade preserves preexisting data', () async {
    final dir = await Directory.systemTemp.createTemp('workout_migration');
    final file = File('${dir.path}/old.sqlite');
    final executor = NativeDatabase(file);
    final old = _VersionOne(executor);
    await old.customStatement('CREATE TABLE user_data (note TEXT)');
    await old.customStatement("INSERT INTO user_data VALUES ('keep')");
    await old.close();
    final upgraded = AppDatabase.forTesting(NativeDatabase(file));
    try {
      await WorkoutRepository(upgraded).seed();
      expect(
        (await upgraded.customSelect('SELECT note FROM user_data').getSingle())
            .read<String>('note'),
        'keep',
      );
      expect(await WorkoutRepository(upgraded).list('workout'), hasLength(4));
    } finally {
      await upgraded.close();
      await dir.delete(recursive: true);
    }
  });
}

class _VersionOne extends AppDatabase {
  _VersionOne(super.executor) : super.forTesting();
  @override
  int get schemaVersion => 1;
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (_) async {});
}
