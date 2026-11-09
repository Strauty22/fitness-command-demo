import 'package:drift/native.dart';

// Native execution is only used by automated tests in this web-only project.
NativeDatabase openDemoDatabase() => NativeDatabase.memory();
