import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'data/exercise_library_repository.dart';
import 'exercise_library_detail.dart';

class ExerciseLibraryScreen extends ConsumerStatefulWidget {
  const ExerciseLibraryScreen({super.key});
  @override
  ConsumerState<ExerciseLibraryScreen> createState() =>
      _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends ConsumerState<ExerciseLibraryScreen> {
  String query = '';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Exercises'),
      actions: [
        IconButton(
          tooltip: 'Manage workout templates',
          onPressed: () => context.push('/programs'),
          icon: const Icon(Icons.tune),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Search exercises',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) =>
                setState(() => query = value.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: ref
              .watch(exerciseLibraryProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Could not load exercises: $e')),
                data: (all) {
                  final filtered = all
                      .where((e) => e.name.toLowerCase().contains(query))
                      .toList();
                  if (filtered.isEmpty) {
                    return const Center(child: Text('No matching exercises.'));
                  }
                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final exercise = filtered[index];
                      return ListTile(
                        key: ValueKey('library-exercise-${exercise.id}'),
                        title: Text(exercise.name),
                        subtitle: exercise.archived
                            ? const Text('Archived')
                            : null,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ExerciseLibraryDetail(exercise: exercise),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
        ),
      ],
    ),
  );
}
