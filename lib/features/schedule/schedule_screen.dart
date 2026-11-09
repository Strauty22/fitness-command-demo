import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../workout/data/workout_repository.dart';
import 'program_week_override.dart';

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});
  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  DateTime date = DateTime.now();
  @override
  Widget build(BuildContext context) {
    ref.watch(managementRevisionProvider);
    final repo = ref.watch(workoutRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly schedule')),
      body: ref
          .watch(managementReadyProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e'),
            data: (_) => FutureBuilder<List<WorkoutRecord>>(
              future: repo.list('program'),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Text('${snapshot.error}');
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final monday = DateTime(
                  date.year,
                  date.month,
                  date.day - date.weekday + 1,
                );
                return ListView(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Previous week',
                          onPressed: () => setState(
                            () => date = date.subtract(const Duration(days: 7)),
                          ),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text(
                          'Week of ${monday.toIso8601String().substring(0, 10)}',
                        ),
                        IconButton(
                          tooltip: 'Next week',
                          onPressed: () => setState(
                            () => date = date.add(const Duration(days: 7)),
                          ),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    for (final p in snapshot.data!) ...[
                      ListTile(
                        title: Text(p.name),
                        subtitle: Text(
                          'Rotation: ${(p.values['cycle'] as List)[rotationIndex(date, DateTime.parse(p.values['anchor'] as String), (p.values['cycle'] as List).length, override: p.values['weekOverride'] as int?)]}${p.values['weekOverride'] == null ? ' (automatic)' : ' (manual override)'}',
                        ),
                      ),
                      ProgramWeekOverride(program: p),
                      for (var day = 0; day < 7; day++)
                        FutureBuilder<List<WorkoutRecord>>(
                          future: repo.scheduleFor(
                            p.id,
                            DateTime(
                              monday.year,
                              monday.month,
                              monday.day + day,
                            ),
                          ),
                          builder: (context, s) => ListTile(
                            title: Text(
                              [
                                'Monday',
                                'Tuesday',
                                'Wednesday',
                                'Thursday',
                                'Friday',
                                'Saturday',
                                'Sunday',
                              ][day],
                            ),
                            subtitle: Text(
                              s.hasError
                                  ? '${s.error}'
                                  : s.data?.map((r) => r.name).join(', ') ??
                                        'Loading…',
                            ),
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
    );
  }
}
