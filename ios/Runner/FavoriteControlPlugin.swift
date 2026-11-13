import Flutter
import UIKit
import WidgetKit

/// The native end of the Dart FavoriteControlService: stores the star state for the lock-screen control and
/// forwards the control's presses to Dart.
class FavoriteControlPlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.devid.musly/favorite_control", binaryMessenger: registrar.messenger())
    let instance = FavoriteControlPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    NotificationCenter.default.addObserver(
      instance, selector: #selector(toggleRequested),
      name: FavoriteControlState.toggleRequested, object: nil)
  }

  @objc private func toggleRequested() {
    channel.invokeMethod("toggle", arguments: nil)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "setState" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let starred = (call.arguments as? [String: Any])?["starred"] as? Bool else {
      result(FlutterError(code: "INVALID_ARGS", message: "setState needs a bool 'starred'", details: nil))
      return
    }
    guard let defaults = FavoriteControlState.defaults else {
      result(FlutterError(code: "NO_APP_GROUP", message: FavoriteControlState.appGroup, details: nil))
      return
    }
    defaults.set(starred, forKey: FavoriteControlState.starredKey)
    if #available(iOS 18.0, *) {
      ControlCenter.shared.reloadControls(ofKind: FavoriteControlState.controlKind)
    }
    result(nil)
  }
}
