import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import 'ride.dart';

class RideRepository {
  final AppDatabase db;
  RideRepository(this.db);
  Future<bool> isDeleted(String id) async =>
      (await db
              .customSelect(
                'SELECT id FROM deleted_rides WHERE id = ?',
                variables: [Variable.withString(id)],
              )
              .get())
          .isNotEmpty;

  Future<void> deleteHistory(String id) => db.transaction(() async {
    final ride = await get(id);
    if (ride == null || ride.status != 'completed') {
      throw StateError('Only completed rides can be deleted');
    }
    await db.customStatement('INSERT INTO deleted_rides(id) VALUES (?)', [id]);
    await db.customStatement('DELETE FROM ride_points WHERE ride_id = ?', [id]);
    await db.customStatement('DELETE FROM ride_sessions WHERE id = ?', [id]);
  });

  Future<Ride?> _capture(String id) async {
    final rows = await db
        .customSelect(
          'SELECT payload FROM ride_sessions WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .get();
    return rows.isEmpty
        ? null
        : Ride(
            Map<String, dynamic>.from(
              jsonDecode(rows.single.read<String>('payload')) as Map,
            ),
          );
  }

  Future<Ride> _annotated(Ride ride) async {
    final rows = await db
        .customSelect(
          'SELECT name, personal_best, notes, description FROM ride_annotations WHERE ride_id = ?',
          variables: [Variable.withString(ride.id)],
        )
        .get();
    if (rows.isEmpty) return Ride({...ride.data, 'personalBest': false});
    return Ride({
      ...ride.data,
      if (rows.single.readNullable<String>('name') != null)
        'name': rows.single.read<String>('name'),
      'personalBest': rows.single.read<int>('personal_best') != 0,
      if (rows.single.readNullable<String>('description') != null)
        'description': rows.single.read<String>('description'),
      if (rows.single.readNullable<String>('notes') != null)
        'notes': rows.single.read<String>('notes'),
    });
  }

  Future<Ride?> get(String id) async {
    final ride = await _capture(id);
    return ride == null ? null : _annotated(ride);
  }

  Future<void> annotate(
    String id, {
    required bool personalBest,
    String? name,
  }) => db.transaction(() async {
    final ride = await _capture(id);
    if (ride == null || ride.status != 'completed') {
      throw StateError('Only saved rides can be annotated');
    }
    await db.customStatement(
      'INSERT INTO ride_annotations(ride_id,name,personal_best) VALUES (?,?,?) ON CONFLICT(ride_id) DO UPDATE SET name=COALESCE(excluded.name,ride_annotations.name), personal_best=excluded.personal_best',
      [id, name, personalBest ? 1 : 0],
    );
  });

  Future<void> saveDescription(
    String id,
    String description,
  ) => db.transaction(() async {
    final ride = await _capture(id);
    if (ride == null || ride.status != 'completed') {
      throw StateError('Only saved rides can have their description edited');
    }
    await db.customStatement(
      'INSERT INTO ride_annotations(ride_id,description) VALUES (?,?) ON CONFLICT(ride_id) DO UPDATE SET description=excluded.description',
      [id, description],
    );
  });

  Future<void> saveNotes(String id, String notes) => db.transaction(() async {
    final ride = await _capture(id);
    if (ride == null || ride.status != 'completed') {
      throw StateError('Only saved rides can have their notes edited');
    }
    await db.customStatement(
      'INSERT INTO ride_annotations(ride_id,notes) VALUES (?,?) ON CONFLICT(ride_id) DO UPDATE SET notes=excluded.notes',
      [id, notes],
    );
  });

  Future<List<Ride>> history() async {
    final rows = await db
        .customSelect(
          "SELECT payload FROM ride_sessions WHERE status = 'completed' ORDER BY ended_at DESC",
        )
        .get();
    return Future.wait([
      for (final row in rows)
        _annotated(
          Ride(
            Map<String, dynamic>.from(
              jsonDecode(row.read<String>('payload')) as Map,
            ),
          ),
        ),
    ]);
  }

  Future<int> lastSequence(String id) async =>
      (await db
              .customSelect(
                'SELECT COALESCE(MAX(sequence),0) AS n FROM ride_points WHERE ride_id = ?',
                variables: [Variable.withString(id)],
              )
              .getSingle())
          .read<int>('n');
  Future<List<RidePoint>> points(String id) async =>
      (await db
              .customSelect(
                'SELECT payload FROM ride_points WHERE ride_id = ? AND accepted = 1 ORDER BY sequence',
                variables: [Variable.withString(id)],
              )
              .get())
          .map(
            (row) => RidePoint.fromJson(
              Map<String, dynamic>.from(
                jsonDecode(row.read<String>('payload')) as Map,
              ),
            ),
          )
          .toList();

  /// Native capture is durable even when Flutter is suspended. Mirror it atomically into Drift.
  Future<void> importCapture(
    Ride ride,
    List<RidePoint> points,
  ) => db.transaction(() async {
    if (await isDeleted(ride.id)) return;
    final existing = await _capture(ride.id);
    if (existing?.status == 'completed' &&
        jsonEncode(existing!.data) != jsonEncode(ride.data)) {
      throw StateError('Completed rides cannot be overwritten');
    }
    await db.customStatement(
      'INSERT INTO ride_sessions(id,status,started_at,ended_at,payload) VALUES (?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET status=excluded.status, ended_at=excluded.ended_at, payload=excluded.payload',
      [
        ride.id,
        ride.status,
        ride.started.toIso8601String(),
        ride.ended?.toIso8601String(),
        jsonEncode(ride.data),
      ],
    );
    for (final point in points) {
      if (!point.latitude.isFinite ||
          !point.longitude.isFinite ||
          point.latitude.abs() > 90 ||
          point.longitude.abs() > 180) {
        continue;
      }
      await db.customStatement(
        'INSERT OR IGNORE INTO ride_points(ride_id,sequence,recorded_at,latitude,longitude,accepted,segment,payload) VALUES (?,?,?,?,?,?,?,?)',
        [
          ride.id,
          point.sequence,
          point.time.toIso8601String(),
          point.latitude,
          point.longitude,
          point.accepted ? 1 : 0,
          point.segment,
          jsonEncode(point.toJson()),
        ],
      );
    }
    if (ride.status == 'discarded') {
      await db.customStatement('DELETE FROM ride_points WHERE ride_id = ?', [
        ride.id,
      ]);
    }
  });
}

final rideRepositoryProvider = Provider(
  (ref) => RideRepository(ref.watch(databaseProvider)),
);
final rideRevisionProvider = NotifierProvider<RideRevision, int>(
  RideRevision.new,
);

class RideRevision extends Notifier<int> {
  @override
  int build() => 0;
  void refresh() => state++;
}

final rideHistoryProvider = FutureProvider<List<Ride>>((ref) {
  ref.watch(rideRevisionProvider);
  return ref.watch(rideRepositoryProvider).history();
});
final ridePointsProvider = FutureProvider.family<List<RidePoint>, String>((
  ref,
  id,
) {
  ref.watch(rideRevisionProvider);
  return ref.watch(rideRepositoryProvider).points(id);
});
