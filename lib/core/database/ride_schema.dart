import 'package:drift/drift.dart';

Future<void> createRideSchema(GeneratedDatabase db) async {
  for (final sql in [
    """CREATE TABLE IF NOT EXISTS ride_sessions (
      id TEXT PRIMARY KEY, status TEXT NOT NULL,
      started_at TEXT NOT NULL, ended_at TEXT, payload TEXT NOT NULL)""",
    """CREATE UNIQUE INDEX IF NOT EXISTS one_live_ride ON ride_sessions((1))
      WHERE status IN ('recording','paused','review')""",
    """CREATE TABLE IF NOT EXISTS ride_points (
      ride_id TEXT NOT NULL REFERENCES ride_sessions(id), sequence INTEGER NOT NULL,
      recorded_at TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL,
      accepted INTEGER NOT NULL, segment INTEGER NOT NULL, payload TEXT NOT NULL,
      PRIMARY KEY (ride_id,sequence))""",
    """CREATE TABLE IF NOT EXISTS ride_map_tiles (
      tile_key TEXT PRIMARY KEY, bytes BLOB NOT NULL, expires_at INTEGER NOT NULL,
      fetched_at INTEGER NOT NULL, etag TEXT, modified TEXT)""",
  ]) {
    await db.customStatement(sql);
  }
}

// Retain only deleted IDs so native capture recovery cannot restore deleted history.
Future<void> createRideDeletionSchema(GeneratedDatabase db) =>
    db.customStatement(
      'CREATE TABLE IF NOT EXISTS deleted_rides (id TEXT PRIMARY KEY)',
    );

// User annotations are separate from immutable native GPS capture payloads.
Future<void> createRideAnnotationsSchema(GeneratedDatabase db) =>
    db.customStatement(
      """CREATE TABLE IF NOT EXISTS ride_annotations (
    ride_id TEXT PRIMARY KEY REFERENCES ride_sessions(id) ON DELETE CASCADE,
    name TEXT, personal_best INTEGER NOT NULL DEFAULT 0, notes TEXT, description TEXT)""",
    );
