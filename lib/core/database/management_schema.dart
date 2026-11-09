import 'package:drift/drift.dart';

const managementSchema = [
  '''CREATE TABLE IF NOT EXISTS management_records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kind TEXT NOT NULL,
    parent_id INTEGER REFERENCES management_records(id),
    position INTEGER NOT NULL DEFAULT 0,
    archived INTEGER NOT NULL DEFAULT 0,
    payload TEXT NOT NULL
  )''',
  '''CREATE INDEX IF NOT EXISTS management_parent ON management_records(kind, parent_id, position)''',
  '''CREATE TABLE IF NOT EXISTS completed_snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    completed_at TEXT NOT NULL,
    payload TEXT NOT NULL
  )''',
  '''CREATE TRIGGER IF NOT EXISTS immutable_snapshot_update BEFORE UPDATE ON completed_snapshots BEGIN SELECT RAISE(ABORT, 'Completed snapshots are immutable'); END''',
  '''CREATE TRIGGER IF NOT EXISTS immutable_snapshot_delete BEFORE DELETE ON completed_snapshots BEGIN SELECT RAISE(ABORT, 'Completed snapshots are immutable'); END''',
];

Future<void> createManagementSchema(GeneratedDatabase db) async {
  for (final sql in managementSchema) {
    await db.customStatement(sql);
  }
}
