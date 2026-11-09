import '../cycling/ride_history_section.dart';
import 'progress_records.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../strength/data/session_repository.dart';
import '../strength/data/strength_session.dart';

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Progress')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const ProgressRecords(),
        const RideHistorySection(progress: true),
        ref
            .watch(sessionHistoryProvider)
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (sessions) {
                final records =
                    <
                      int,
                      List<
                        (
                          String,
                          String,
                          Map<String, dynamic>,
                          Map<String, dynamic>,
                        )
                      >
                    >{};
                for (final session in sessions.where(
                  (s) => s.status == 'completed',
                )) {
                  for (final exercise in session.loggedExercises) {
                    for (final set in (exercise['actualSets'] as List).where(
                      (s) => s['completed'] == true,
                    )) {
                      records
                          .putIfAbsent(exercise['exerciseId'] as int, () => [])
                          .add((
                            exercise['name'] as String,
                            session.endedAt!.toLocal().toString().substring(
                              0,
                              10,
                            ),
                            Map<String, dynamic>.from(
                              exercise['target'] as Map,
                            ),
                            Map<String, dynamic>.from(set as Map),
                          ));
                    }
                  }
                }
                if (records.isEmpty) {
                  return const Center(
                    child: Text(
                      'Complete sets to see exercise performance here.',
                    ),
                  );
                }
                return ListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final entries in records.values)
                      Card(
                        child: ExpansionTile(
                          title: Text(entries.first.$1),
                          subtitle: Text(
                            'Latest: ${setMeasurementText(entries.first.$3, entries.first.$4)}',
                          ),
                          children: [
                            for (final entry in entries)
                              ListTile(
                                title: Text(
                                  setMeasurementText(entry.$3, entry.$4),
                                ),
                                subtitle: Text(entry.$2),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
      ],
    ),
  );
}
