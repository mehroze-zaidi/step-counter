import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'data/step_repository.dart';
import 'state/step_controller.dart';
import 'sync/background_sync.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = StepRepository();
  if (Platform.isIOS) {
    // Before runApp: a HealthKit background wake may be waiting on this.
    await BackgroundSync.attach(repository);
  }
  runApp(StepCounterApp(controller: StepController(repository)..init()));
}

class StepCounterApp extends StatelessWidget {
  const StepCounterApp({super.key, required this.controller});

  final StepController controller;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D5B), brightness: b),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'Step Counter',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: HomePage(controller: controller),
    );
  }
}
