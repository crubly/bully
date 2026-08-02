import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let engine = engineBridge.pluginRegistry as? FlutterEngine else { return }
    let channel = FlutterMethodChannel(
      name: "bully/app_icon",
      binaryMessenger: engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setIcon":
        let args = call.arguments as? [String: Any]
        let name = args?["name"] as? String ?? "default"
        let iconName = name == "alt" ? "AppIcon-Alt" : nil
        guard UIApplication.shared.supportsAlternateIcons else {
          result(nil)
          return
        }
        UIApplication.shared.setAlternateIconName(iconName) { _ in }
        result(nil)
      case "currentIcon":
        let current = UIApplication.shared.alternateIconName
        result(current == "AppIcon-Alt" ? "alt" : "default")
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // iOS has no API to block another app/OS surface from capturing our
    // window (no FLAG_SECURE equivalent for arbitrary content) — the best
    // available mitigation is detecting an active screen recording/AirPlay
    // mirror via UIScreen.isCaptured and telling Dart to swap in a blurred
    // placeholder for as long as it stays true.
    let screenPrivacyChannel = FlutterMethodChannel(
      name: "bully/screen_privacy",
      binaryMessenger: engine.binaryMessenger
    )
    screenPrivacyChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "setSecure":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    NotificationCenter.default.addObserver(
      forName: UIScreen.capturedDidChangeNotification,
      object: nil,
      queue: .main
    ) { _ in
      screenPrivacyChannel.invokeMethod("captureStateChanged", arguments: UIScreen.main.isCaptured)
    }
  }
}
