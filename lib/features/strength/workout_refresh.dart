import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/session_repository.dart';
import 'data/workout_discovery.dart';

class WorkoutRefresh extends ConsumerStatefulWidget {
  final Widget child;
  const WorkoutRefresh({super.key, required this.child});
  @override
  ConsumerState<WorkoutRefresh> createState() => _WorkoutRefreshState();
}

class _WorkoutRefreshState extends ConsumerState<WorkoutRefresh>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void refresh() {
    ref.invalidate(workoutChoicesProvider);
    ref.invalidate(unfinishedSessionProvider);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
