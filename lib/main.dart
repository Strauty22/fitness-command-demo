import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/database/app_database.dart';
import 'demo/sample_data.dart';
import 'demo/workout_templates.dart';

void main() => runApp(const DemoBootstrap());

class DemoBootstrap extends StatefulWidget {
  const DemoBootstrap({super.key});
  @override
  State<DemoBootstrap> createState() => _DemoBootstrapState();
}

class _DemoBootstrapState extends State<DemoBootstrap> {
  final database = AppDatabase();
  Future<void> prepareDemo() async {
    await seedDemo(database);
    await loadDemoWorkoutTemplates(database);
  }

  late Future<void> ready = prepareDemo();
  @override
  void dispose() {
    database.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: ready,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError) {
        return ProviderScope(
          overrides: [databaseProvider.overrideWithValue(database)],
          child: const FitnessCommandApp(),
        );
      }
      return MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: snapshot.hasError
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Demo storage could not open. Allow browser storage and check your connection.',
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            ready = prepareDemo();
                          }),
                          child: const Text('Retry'),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
        ),
      );
    },
  );
}
