import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';

import '../data/activity_snapshot.dart';
import '../data/step_repository.dart';

/// Must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist and the
/// identifier registered in AppDelegate.swift.
const backgroundRefreshTaskId = 'com.example.stepCounter.refresh';

/// Entry point for workmanager's background isolate (BGAppRefreshTask on iOS).
/// This is the fallback for when HealthKit background delivery is throttled.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final snapshot = await StepRepository().sync(reason: 'bgRefresh');
    // A locked device is expected here; report success so iOS doesn't
    // penalise future scheduling. Real errors ask for a retry.
    return snapshot.status != SyncStatus.error;
  });
}

/// Two background paths:
/// 1. HealthKit background delivery (native, ios/Runner/HealthBackgroundDelivery.swift):
///    iOS wakes the app — even relaunching it — when new steps are written.
/// 2. workmanager periodic refresh: best-effort, roughly every 30+ minutes.
class BackgroundSync {
  static const _channel = MethodChannel('step_counter/background_delivery');

  /// Call before `runApp`. When iOS relaunches the app in the background for
  /// HealthKit, native code holds the wake until this handler is attached.
  static Future<void> attach(StepRepository repository) async {
    await Workmanager().initialize(callbackDispatcher);

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onHealthDataChanged') return null;
      final reason = (call.arguments as Map?)?['reason'] as String? ?? 'observer';

      // Unlock notifications only matter if the last attempt failed because
      // the device was locked.
      if (reason == 'unlocked') {
        final cached = await repository.readCache();
        if (cached?.status != SyncStatus.locked) return null;
      }
      if (!await repository.authorizationRequested) return null;

      await repository.sync(reason: reason);
      return null; // replying releases HealthKit's completion handler
    });
    await _channel.invokeMethod<void>('attach');
  }

  /// Call once Health access has been requested. Idempotent.
  static Future<void> enable() async {
    await _channel.invokeMethod<void>('enable');
    await Workmanager().registerPeriodicTask(
      backgroundRefreshTaskId,
      backgroundRefreshTaskId,
      frequency: const Duration(minutes: 30),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }
}
