import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Plugins available inside workmanager's background isolate.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // BGTaskScheduler handlers must be registered before launch finishes.
    // Identifier must match Info.plist and lib/sync/background_sync.dart.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.example.stepCounter.refresh",
      earliestBeginInSeconds: NSNumber(value: 30 * 60))

    HealthBackgroundDelivery.shared.bootstrap()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HealthBackgroundDelivery") {
      HealthBackgroundDelivery.shared.register(with: registrar)
    }
  }
}
