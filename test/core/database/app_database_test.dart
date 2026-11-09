import 'dart:io';
import 'package:drift/native.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Database survives reopening a local file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fitness_command_test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/foundation.sqlite');
    final database = AppDatabase.forTesting(NativeDatabase(file));
    try {
      await database.customStatement(
        'CREATE TABLE persistence_probe (value TEXT NOT NULL)',
      );
      await database.customStatement(
        "INSERT INTO persistence_probe VALUES ('saved')",
      );
    } finally {
      await database.close();
    }
    final reopened = AppDatabase.forTesting(NativeDatabase(file));
    try {
      final row = await reopened
          .customSelect('SELECT value FROM persistence_probe')
          .getSingle();
      expect(row.read<String>('value'), 'saved');
      final version = await reopened
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 9);
    } finally {
      await reopened.close();
    }
  });
}
