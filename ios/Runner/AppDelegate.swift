import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // First thing: when did this process start? An intent performed a
    // breath later was the reason it started. See LaunchAnchor.
    LaunchAnchor.record()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Registered like a plugin, and for the same reason: it needs a
    // messenger and it needs the scene's URLs.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SondrLiveActivity") {
      SessionActivityChannel.shared.register(with: registrar)
    }
  }
}
