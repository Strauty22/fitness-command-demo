import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class NavigationShell extends StatelessWidget {
  final Widget child;
  const NavigationShell({super.key, required this.child});
  static const destinations = [
    ('Home', '/', Icons.home_outlined),
    ('Exercises', '/exercises', Icons.fitness_center),
    ('History', '/history', Icons.calendar_month_outlined),
    ('Progress', '/progress', Icons.bar_chart),
    ('Settings', '/settings', Icons.settings_outlined),
  ];
  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final index = destinations.indexWhere(
      (d) => d.$2 != '/' && path.startsWith(d.$2),
    );
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          indicatorColor: Colors.transparent,
          iconTheme: WidgetStateProperty.resolveWith(
            (s) => IconThemeData(
              color: s.contains(WidgetState.selected)
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (s) => TextStyle(
              fontSize: 11,
              color: s.contains(WidgetState.selected)
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
          ),
        ),
        child: NavigationBar(
          height: 64,
          selectedIndex: path.startsWith('/programs')
              ? 1
              : index < 0
              ? 0
              : index,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (i) => context.go(destinations[i].$2),
          destinations: [
            for (final d in destinations)
              NavigationDestination(icon: Icon(d.$3), label: d.$1),
          ],
        ),
      ),
    );
  }
}
