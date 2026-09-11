import Flutter
import Foundation

/// MethodChannel `de.verspaetomat/geofence`, see docs/15-geofence.md.
final class GeofenceChannel {
  static let name = "de.verspaetomat/geofence"
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.name, binaryMessenger: messenger)
    let manager = GeofenceManager.shared
    manager.onNudgeTapped = { [channel] payload in
      DispatchQueue.main.async { channel.invokeMethod("nudgeTapped", arguments: payload) }
    }
    manager.onUmbrellaExit = { [channel] in
      DispatchQueue.main.async { channel.invokeMethod("umbrellaExit", arguments: nil) }
    }
    manager.onPushToken = { [channel] token in
      DispatchQueue.main.async { channel.invokeMethod("pushToken", arguments: ["platform": "ios", "token": token]) }
    }
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "configure":
        manager.configure(args) { result($0) }
      case "requestPermission":
        manager.requestPermission(always: args["always"] as? Bool ?? false) { result($0) }
      case "status":
        manager.status { result($0) }
      case "registerPush":
        manager.registerPush { result($0) }
      case "stop":
        manager.stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
