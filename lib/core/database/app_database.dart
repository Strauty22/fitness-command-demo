import 'ride_schema.dart';
import 'package:drift/drift.dart';
import 'management_schema.dart';
import 'session_schema.dart';
import 'demo_connection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Local schema uses parameterized Drift SQL repositories.

class AppDatabase extends GeneratedDatabase {
  AppDatabase() : super(openDemoDatabase());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await createManagementSchema(this);
      await createSessionSchema(this);
      await enableHistoryEditing();
      await createRideSchema(this);
      await createRideDeletionSchema(this);
      await createRideAnnotationsSchema(this);
    },
    onUpgrade: (_, from, to) async {
      if (from < 2) await createManagementSchema(this);
      if (from < 3) await createSessionSchema(this);
      if (from < 4) await enableHistoryEditing();
      if (from < 5) await createRideSchema(this);
      if (from < 6) await createRideDeletionSchema(this);
      if (from < 7) {
        await createRideAnnotationsSchema(this);
      } else {
        if (from < 8) {
          await customStatement(
            'ALTER TABLE ride_annotations ADD COLUMN notes TEXT',
          );
        }
        if (from < 9) {
          await customStatement(
            'ALTER TABLE ride_annotations ADD COLUMN description TEXT',
          );
        }
      }
    },
    beforeOpen: (_) async => customStatement('PRAGMA foreign_keys = ON'),
  );

  Future<void> enableHistoryEditing() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS history_edit_permission (session_id INTEGER PRIMARY KEY)',
    );
    for (final name in [
      'immutable_strength_update',
      'immutable_strength_delete',
      'immutable_snapshot_update',
      'immutable_snapshot_delete',
    ]) {
      await customStatement('DROP TRIGGER IF EXISTS $name');
    }
    for (final operation in ['UPDATE', 'DELETE']) {
      final suffix = operation.toLowerCase();
      await customStatement(
        "CREATE TRIGGER immutable_strength_$suffix BEFORE $operation ON strength_sessions WHEN OLD.status IN ('completed','cancelled') AND NOT EXISTS (SELECT 1 FROM history_edit_permission WHERE session_id = OLD.id) BEGIN SELECT RAISE(ABORT, 'Use explicit history editing'); END",
      );
      await customStatement(
        "CREATE TRIGGER immutable_snapshot_$suffix BEFORE $operation ON completed_snapshots WHEN NOT EXISTS (SELECT 1 FROM history_edit_permission WHERE session_id = json_extract(OLD.payload, '\$.sessionId')) BEGIN SELECT RAISE(ABORT, 'Use explicit history editing'); END",
      );
    }
  }

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final databaseReadyProvider = FutureProvider<void>((ref) async {
  await ref.watch(databaseProvider).customSelect('SELECT 1').get();
});
