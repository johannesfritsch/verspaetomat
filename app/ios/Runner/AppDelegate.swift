import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var geofenceChannel: GeofenceChannel?
  private var audioChannel: FlutterMethodChannel?
  private var savedAudio: (AVAudioSession.Category, AVAudioSession.CategoryOptions)?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Created at launch so a region event that relaunches the app in the background is delivered.
    GeofenceManager.shared.start()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    GeofenceManager.shared.pushTokenArrived(hex)
  }

  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    GeofenceManager.shared.pushRegistrationFailed(error.localizedDescription)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GeofenceChannel") {
      geofenceChannel = GeofenceChannel(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AudioChannel") {
      audioChannel = makeAudioChannel(registrar.messenger())
    }
  }

  /// `de.verspaetomat/audio` (docs/51 §9b): a puzzle's film plays with sound only when the phone
  /// is not muted. video_player sets the session to `.playback`, which ignores the ring/silent
  /// switch; `ambient` puts it on `.ambient`, which obeys it, and `restore` puts back what was
  /// there before `remember`.
  private func makeAudioChannel(_ messenger: FlutterBinaryMessenger) -> FlutterMethodChannel {
    let channel = FlutterMethodChannel(name: "de.verspaetomat/audio", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      let session = AVAudioSession.sharedInstance()
      switch call.method {
      case "remember":
        if self?.savedAudio == nil { self?.savedAudio = (session.category, session.categoryOptions) }
        result(nil)
      case "ambient":
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        result(nil)
      case "restore":
        if let (category, options) = self?.savedAudio {
          try? session.setCategory(category, options: options)
        }
        self?.savedAudio = nil
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    return channel
  }
}
