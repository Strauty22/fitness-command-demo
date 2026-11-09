import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final database = ref.watch(databaseReadyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('Fitness Command uses a dark theme with green accents.'),
          const SizedBox(height: 16),
          database.when(
            data: (_) => const Text(
              'Demo storage ready. Fictional sample records and demo edits stay in this browser. Clear this site’s storage to reset. Cycling and GPS are simulated; audio and background recording are not active.',
            ),
            loading: () => const Text('Opening local storage…'),
            error: (error, stack) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Local storage could not be opened.'),
                TextButton(
                  onPressed: () => ref.invalidate(databaseReadyProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
