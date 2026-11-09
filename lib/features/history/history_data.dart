import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../strength/data/session_repository.dart';
import '../strength/data/strength_session.dart';
import '../cycling/data/ride_repository.dart';
import '../cycling/data/ride.dart';

class HistoryEntry {
  final StrengthSession? session;
  final Ride? ride;
  HistoryEntry.strength(StrengthSession value) : session = value, ride = null;
  HistoryEntry.cycling(Ride value) : ride = value, session = null;
  DateTime get date => session?.endedAt ?? ride?.ended ?? ride!.started;
  String get key =>
      session != null ? 'strength-${session!.id}' : 'ride-${ride!.id}';
}

final combinedHistoryProvider = FutureProvider<List<HistoryEntry>>((ref) async {
  ref.watch(sessionRevisionProvider);
  ref.watch(rideRevisionProvider);
  final strength = ref.watch(sessionRepositoryProvider).history();
  final rides = ref.watch(rideRepositoryProvider).history();
  final entries = [
    for (final session in await strength) HistoryEntry.strength(session),
    for (final ride in await rides) HistoryEntry.cycling(ride),
  ];
  entries.sort((a, b) {
    final date = b.date.compareTo(a.date);
    return date != 0 ? date : b.key.compareTo(a.key);
  });
  return entries;
});

final completedWorkoutCountProvider = FutureProvider<int>((ref) async {
  ref.watch(sessionRevisionProvider);
  ref.watch(rideRevisionProvider);
  final row = await ref
      .watch(databaseProvider)
      .customSelect(
        "SELECT (SELECT COUNT(*) FROM strength_sessions WHERE status = 'completed') + (SELECT COUNT(*) FROM ride_sessions WHERE status = 'completed') AS total",
      )
      .getSingle();
  return row.read<int>('total');
});
