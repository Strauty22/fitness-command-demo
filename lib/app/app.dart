import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'router.dart';

class FitnessCommandApp extends ConsumerWidget {
  const FitnessCommandApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Fitness Command Demo',
    builder: (context, child) => Column(
      children: [
        Material(
          color: const Color(0xff183522),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  'WEB DEMO • Fictional data • Simulated GPS',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          ),
        ),
        Expanded(child: child ?? const SizedBox.shrink()),
      ],
    ),
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: Colors.green,
      brightness: Brightness.light,
    ),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.green,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xff101210),
      cardTheme: const CardThemeData(color: Color(0xff222622)),
    ),
    themeMode: ThemeMode.dark,
    routerConfig: ref.watch(routerProvider),
  );
}
