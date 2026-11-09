import 'package:drift/drift.dart';

const sessionSchema = [
  '''CREATE TABLE IF NOT EXISTS strength_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    status TEXT NOT NULL CHECK(status IN ('active','paused','completed','cancelled')),
    started_at TEXT NOT NULL,
    ended_at TEXT,
    payload TEXT NOT NULL
  )''',
  '''CREATE UNIQUE INDEX IF NOT EXISTS one_unfinished_strength_session
    ON strength_sessions((1)) WHERE status IN ('active','paused')''',
  '''CREATE TRIGGER IF NOT EXISTS immutable_strength_update BEFORE UPDATE ON strength_sessions
    WHEN OLD.status IN ('completed','cancelled') BEGIN SELECT RAISE(ABORT, 'Finished sessions are immutable'); END''',
  '''CREATE TRIGGER IF NOT EXISTS immutable_strength_delete BEFORE DELETE ON strength_sessions
    BEGIN SELECT RAISE(ABORT, 'Sessions cannot be deleted'); END''',
];

Future<void> createSessionSchema(GeneratedDatabase db) async {
  for (final sql in sessionSchema) {
    await db.customStatement(sql);
  }
}
