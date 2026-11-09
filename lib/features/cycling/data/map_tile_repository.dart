import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';

// Synthetic route grid: no network tiles or real location data.
class MapTileRepository {
  MapTileRepository(AppDatabase db);
  final unavailable = ValueNotifier(false);
  Future<Uint8List?> tile(int z, int x, int y) async => null;
  void retry() {}
  void close() => unavailable.dispose();
}

final mapTileRepositoryProvider = Provider((ref) {
  final repo = MapTileRepository(ref.watch(databaseProvider));
  ref.onDispose(repo.close);
  return repo;
});
