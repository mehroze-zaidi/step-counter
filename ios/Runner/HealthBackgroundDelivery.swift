import Flutter
import HealthKit
import UIKit

/// HealthKit background delivery — the one piece no Flutter package handles
/// reliably, so it stays native. Reads, permissions and caching are done in
/// Dart with the `health` and `shared_preferences` packages.
///
/// Flow: HKObserverQuery fires (app alive, suspended, or relaunched by iOS)
/// -> we ask Dart to sync via `onHealthDataChanged` -> when Dart replies (or a
/// timeout hits) we call HealthKit's completion handler. Not calling it makes
/// iOS back off and eventually stop waking the app.
///
/// Channel `step_counter/background_delivery`:
///   Dart -> native: `attach` (Dart handler is ready), `enable` (after auth)
///   native -> Dart: `onHealthDataChanged` {reason}
final class HealthBackgroundDelivery: NSObject {
  static let shared = HealthBackgroundDelivery()

  private static let enabledKey = "HealthBackgroundDelivery.enabled"
  /// HealthKit gives the handler only a short window of background time.
  private let handlerTimeout: TimeInterval = 20

  private let store = HKHealthStore()
  private let types = [HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned)]
  private var observersStarted = false

  private var channel: FlutterMethodChannel?
  private var dartAttached = false
  /// Wakes that arrive before Dart has attached (cold background launch).
  private var pending: [(reason: String, done: () -> Void)] = []

  /// Call from `didFinishLaunching`. When iOS relaunches a terminated app for
  /// background delivery, observers must be re-installed right away.
  func bootstrap() {
    if UserDefaults.standard.bool(forKey: Self.enabledKey) { startObserving() }

    // The Health store is encrypted while the phone is locked, so a wake can
    // fail to read. Give Dart a chance to retry once it unlocks.
    NotificationCenter.default.addObserver(
      forName: UIApplication.protectedDataDidBecomeAvailableNotification,
      object: nil, queue: .main
    ) { [weak self] _ in self?.notifyDart(reason: "unlocked", done: {}) }
  }

  func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "step_counter/background_delivery", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "attach":
        self.dartAttached = true
        let queued = self.pending
        self.pending.removeAll()
        queued.forEach { self.notifyDart(reason: $0.reason, done: $0.done) }
        result(nil)
      case "enable":
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        self.startObserving()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  private func startObserving() {
    guard HKHealthStore.isHealthDataAvailable(), !observersStarted else { return }
    observersStarted = true

    for type in types {
      let query = HKObserverQuery(sampleType: type, predicate: nil) {
        [weak self] _, completionHandler, error in
        let finish = Once()
        let done = { finish.run(completionHandler) }
        guard let self, error == nil else { return done() }
        DispatchQueue.main.asyncAfter(deadline: .now() + self.handlerTimeout, execute: done)
        DispatchQueue.main.async { self.notifyDart(reason: "observer", done: done) }
      }
      store.execute(query)
      // iOS caps step delivery at hourly no matter what we request.
      store.enableBackgroundDelivery(for: type, frequency: .hourly) { ok, error in
        if !ok { NSLog("[HealthBackgroundDelivery] enable failed: \(String(describing: error))") }
      }
    }
  }

  /// Main thread only.
  private func notifyDart(reason: String, done: @escaping () -> Void) {
    guard dartAttached, let channel else {
      pending.append((reason, done))
      return
    }
    channel.invokeMethod("onHealthDataChanged", arguments: ["reason": reason]) { _ in done() }
  }
}

/// Runs a closure at most once, from any thread.
private final class Once {
  private let lock = NSLock()
  private var done = false

  func run(_ body: () -> Void) {
    lock.lock()
    let shouldRun = !done
    done = true
    lock.unlock()
    if shouldRun { body() }
  }
}
