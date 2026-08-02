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
  }
}
