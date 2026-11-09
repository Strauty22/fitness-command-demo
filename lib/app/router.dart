import '../features/strength/workout_completion_screen.dart';
import '../features/cycling/cycling_screen.dart';
import '../features/cycling/ride_summary_screen.dart';
import '../features/exercises/exercise_library_screen.dart';
import 'navigation_shell.dart';
import '../features/workout/custom_workout_screen.dart';
import '../features/history/progress_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/home/home_screen.dart';
import '../features/workout/workout_screen.dart';
import '../features/history/history_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/strength/workout_launch_screen.dart';
import '../features/strength/session_screen.dart';
import '../features/strength/workout_preview_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/cycling',
        builder: (context, state) => const CyclingScreen(),
      ),
      GoRoute(
        path: '/rides/:id',
        builder: (context, state) =>
            SavedRideScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/completed/:id',
        builder: (context, state) => WorkoutCompletionScreen(
          sessionId: int.parse(state.pathParameters['id']!),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => NavigationShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
          GoRoute(
            path: '/custom-workouts/new',
            builder: (context, state) => const CustomWorkoutScreen(),
          ),
          GoRoute(
            path: '/custom-workouts/:id/edit',
            builder: (context, state) => CustomWorkoutScreen(
              workoutId: int.parse(state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/workout',
            builder: (context, state) => const WorkoutLaunchScreen(),
          ),
          GoRoute(
            path: '/workout/:id',
            builder: (context, state) => WorkoutPreviewScreen(
              workoutId: int.parse(state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/exercises',
            builder: (context, state) => const ExerciseLibraryScreen(),
          ),
          GoRoute(
            path: '/programs',
            builder: (context, state) => const WorkoutScreen(),
          ),
          GoRoute(
            path: '/session/:id',
            builder: (context, state) => SessionScreen(
              sessionId: int.parse(state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/history',
            builder: (context, state) => const HistoryScreen(),
          ),
          GoRoute(
            path: '/progress',
            builder: (context, state) => const ProgressScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
