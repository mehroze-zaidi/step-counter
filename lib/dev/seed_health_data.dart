import 'dart:math';

import 'package:health/health.dart';

/// Debug-only: writes a week of fake steps (and active energy for some days)
/// into Apple Health so the UI can be exercised on the simulator. Writing
/// triggers the HKObserverQuery, so the screen should refresh by itself.
Future<void> seedHealthData() async {
  final health = Health();
  await health.configure();
  const types = [HealthDataType.STEPS, HealthDataType.ACTIVE_ENERGY_BURNED];
  await health.requestAuthorization(
    types,
    permissions: [for (final _ in types) HealthDataAccess.READ_WRITE],
  );

  final random = Random();
  final now = DateTime.now();
  for (var i = 6; i >= 0; i--) {
    final day = DateTime(now.year, now.month, now.day - i);
    final start = day.add(const Duration(hours: 8));
    final end = i == 0 && now.isBefore(start.add(const Duration(hours: 1)))
        ? now
        : start.add(const Duration(hours: 1));
    if (!end.isAfter(start)) continue;
    final steps = 3000 + random.nextInt(9000);
    await health.writeHealthData(
      value: steps.toDouble(),
      type: HealthDataType.STEPS,
      startTime: start,
      endTime: end,
    );
    // Leave odd days without Active Energy to exercise the estimate path.
    if (i.isEven) {
      await health.writeHealthData(
        value: steps * 0.045,
        type: HealthDataType.ACTIVE_ENERGY_BURNED,
        startTime: start,
        endTime: end,
      );
    }
  }
}
