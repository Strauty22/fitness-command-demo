import 'package:drift/native.dart';
import 'package:fitness_command/core/database/app_database.dart';
import 'package:fitness_command/features/schedule/program_week_override.dart';
import 'package:fitness_command/features/workout/data/workout_repository.dart';
import 'package:fitness_command/features/workout/record_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late WorkoutRepository repo;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = WorkoutRepository(db);
  });
  tearDown(() => db.close());

  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, {WorkoutRecord? record}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => RecordEditor(
                    kind: 'program',
                    record: record,
                    repo: repo,
                    exercises: const [],
                  ),
                ),
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('new program defaults to today and A/B with only name required', (
    tester,
  ) async {
    await open(tester);
    final today = DateUtils.dateOnly(DateTime.now());
    expect(find.byType(CalendarDatePicker), findsNothing);
    expect(find.text('Program defaults'), findsOneWidget);
    expect(find.textContaining('Manual week index'), findsNothing);
    expect(find.widgetWithText(TextField, 'Sets'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Simple');
    await tester.tap(find.text('Save'));
    await flush(tester);
    final programs = await tester.runAsync(() => repo.list('program'));
    final p = programs!.single;
    expect(p.values['anchor'], today.toIso8601String().substring(0, 10));
    expect(p.values['cycle'], ['Week A', 'Week B']);
    expect(p.values['sets'], 2);
    expect(p.values['reps'], 10);
    expect(p.values['restSeconds'], 90);
    expect(p.values.containsKey('weekOverride'), false);
  });

  testWidgets('editing defaults preserves legacy calendar metadata', (
    tester,
  ) async {
    final id = await tester.runAsync(
      () => repo.create('program', {
        'name': 'Existing',
        'anchor': '2026-12-31',
        'cycle': ['Week A', 'Week B'],
        'sets': 4,
        'reps': 8,
        'weekOverride': 1,
        'notes': 'Keep',
      }),
    );
    final original = await tester.runAsync(() => repo.get(id!));
    await open(tester, record: original);
    expect(find.byKey(const ValueKey('program-anchor')), findsNothing);
    await tester.tap(find.text('Save'));
    await flush(tester);
    expect(
      (await tester.runAsync(() => repo.get(id!)))!.values,
      original!.values,
    );
  });

  testWidgets(
    'named override can be selected and cleared outside program setup',
    (tester) async {
      final id = await tester.runAsync(
        () => repo.create('program', {
          'name': 'Rotation',
          'anchor': '2026-12-31',
          'cycle': ['Week A', 'Week B'],
        }),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  ref.watch(managementRevisionProvider);
                  return FutureBuilder<WorkoutRecord>(
                    future: repo.get(id!),
                    builder: (context, s) => s.hasData
                        ? ProgramWeekOverride(program: s.data!)
                        : const SizedBox(),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await flush(tester);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Week B').last);
      await flush(tester);
      var saved = await tester.runAsync(() => repo.get(id!));
      expect(saved!.values['weekOverride'], 1);
      expect(saved.values['anchor'], '2026-12-31');
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Automatic (calendar)').last);
      await flush(tester);
      saved = await tester.runAsync(() => repo.get(id!));
      expect(saved!.values.containsKey('weekOverride'), false);
      expect(saved.values['anchor'], '2026-12-31');
    },
  );
}
