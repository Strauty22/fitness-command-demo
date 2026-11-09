// The pinned sql.js adapter supports static hosting without special headers.
// ignore: deprecated_member_use
import 'package:drift/web.dart';

WebDatabase openDemoDatabase() => WebDatabase.withStorage(
  // Pinned demo adapter, without cross-origin isolation requirements.
  // ignore: experimental_member_use
  DriftWebStorage.indexedDb('fitness_command_web_demo_v1'),
);
