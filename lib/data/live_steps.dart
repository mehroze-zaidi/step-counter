import 'dart:async';

import 'package:pedometer_2/pedometer_2.dart';

/// Live step count since local midnight from CoreMotion (CMPedometer).
///
/// HealthKit is not a live source: the iPhone flushes motion-chip steps into
/// Apple Health in batches, often minutes apart, so the HealthKit total lags
/// while you walk. CMPedometer reads the motion chip directly and updates
/// every few seconds. It only counts *this iPhone* (no Apple Watch) and only
/// delivers while the app is in the foreground.
class LiveSteps {
  LiveSteps({Pedometer? pedometer}) : _pedometer = pedometer ?? Pedometer();

  final Pedometer _pedometer;
  StreamSubscription<int>? _sub;
  DateTime? _since;

  /// Start of the day the current stream counts from, or null when stopped.
  DateTime? get since => _since;

  /// (Re)starts counting from [dayStart]. Restarting is needed at midnight,
  /// since the native stream is bound to the start date it was opened with.
  void start(DateTime dayStart, void Function(int steps) onSteps) {
    if (_sub != null && _since == dayStart) return;
    stop();
    _since = dayStart;
    // If Motion & Fitness access is denied (or Fitness Tracking is off),
    // CMPedometer reports an error that the plugin swallows, so the stream
    // stays silent and the UI simply keeps showing the HealthKit total.
    _sub = _pedometer
        .stepCountStreamFrom(from: dayStart)
        .listen(
          onSteps,
          onError: (Object _) {}, // e.g. no motion coprocessor
          cancelOnError: false,
        );
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _since = null;
  }
}
