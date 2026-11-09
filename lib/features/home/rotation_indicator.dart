import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/rotation_repository.dart';
import 'package:go_router/go_router.dart';

class RotationIndicator extends ConsumerStatefulWidget {
  const RotationIndicator({super.key});
  @override
  ConsumerState<RotationIndicator> createState() => _RotationIndicatorState();
}

class _RotationIndicatorState extends ConsumerState<RotationIndicator>
    with WidgetsBindingObserver {
  Timer? midnight;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    schedule();
  }

  void schedule() {
    midnight?.cancel();
    final now = DateTime.now();
    midnight = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now),
      () {
        if (mounted) {
          ref.invalidate(rotationProvider);
          schedule();
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(rotationProvider);
      schedule();
    }
  }

  @override
  void dispose() {
    midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: SizedBox(
      height: 48,
      child: ref
          .watch(rotationProvider)
          .when(
            loading: () => const Center(child: Text('Loading rotation...')),
            error: (e, _) => TextButton(
              onPressed: () => ref.invalidate(rotationProvider),
              child: const Text('Retry rotation'),
            ),
            data: (rotation) {
              final week = rotation.week(ref.watch(rotationClockProvider)());
              return Row(
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      week == null
                          ? 'Set Week A starting date'
                          : 'Current Rotation: Week ${week == 0 ? 'A' : 'B'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Create Workout',
                    onPressed: () => context.push('/custom-workouts/new'),
                    icon: const Icon(Icons.add),
                  ),
                  const SizedBox(width: 4),
                ],
              );
            },
          ),
    ),
  );
}
