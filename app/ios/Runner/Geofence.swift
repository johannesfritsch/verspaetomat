import CoreLocation
import Foundation
import UIKit
import UserNotifications

// Station geofencing per docs/15-geofence.md. The phone decides, nothing is stored but
// the current region set; the only network call is the nearby query on umbrella exit.

struct GeofenceStation: Codable, Equatable {
  let id: String; let name: String; let lat: Double; let lon: Double
  var location: CLLocation { CLLocation(latitude: lat, longitude: lon) }
}

struct GeofenceConfig: Codable {
  var apiUrl: String; var token: String; var enabled: Bool; var riding: Bool
  var stations: [GeofenceStation]; var umbrellaRadiusM: Double; var stationRadiusM: Double
  var quietFrom: String?; var quietTo: String?
}

/// Pure rules, kept free of CoreLocation state so they can be unit-tested.
enum GeofenceRules {
  static let maxFrequent = 16, maxNearest = 3
  static let nudgeDelay: TimeInterval = 60, watchWindow: TimeInterval = 25, nudgeCooldown: TimeInterval = 30 * 60
  static let vehicleSpeed: CLLocationSpeed = 8 // m/s: faster than a walk, the phone is passing through

  /// "22:00"/"06:00" style window in local time; a window crossing midnight is allowed.
  static func isQuiet(now: Date, from: String?, to: String?, calendar: Calendar = .current) -> Bool {
    guard let f = minutes(from), let t = minutes(to), f != t else { return false }
    let c = calendar.dateComponents([.hour, .minute], from: now)
    let n = (c.hour ?? 0) * 60 + (c.minute ?? 0)
    return f < t ? (n >= f && n < t) : (n >= f || n < t)
  }

  static func minutes(_ s: String?) -> Int? {
    guard let s = s else { return nil }
    let p = s.split(separator: ":").compactMap { Int($0) }
    guard p.count == 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]) else { return nil }
    return p[0] * 60 + p[1]
  }

  /// Frequent stations first (capped), then nearest ones not already present (capped).
  static func regionSet(frequent: [GeofenceStation], nearest: [GeofenceStation]) -> [GeofenceStation] {
    var out: [GeofenceStation] = []
    for s in frequent where !out.contains(where: { $0.id == s.id }) && out.count < maxFrequent { out.append(s) }
    var added = 0
    for s in nearest where !out.contains(where: { $0.id == s.id }) && added < maxNearest {
      out.append(s)
      added += 1
    }
    return out
  }

  /// A fix that proves the phone is not standing at the station: outside the
  /// radius, or moving at vehicle speed through it.
  static func fixCancelsNudge(_ fix: CLLocation, station: CLLocation, radius: Double) -> Bool {
    if fix.distance(from: station) > radius { return true }
    return fix.speed >= vehicleSpeed
  }

  /// `{stations:[{id,name,lat,lon,distance_m}], ...}` → the nearest three.
  static func parseNearby(_ data: Data) -> [GeofenceStation] {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let list = root["stations"] as? [[String: Any]] else { return [] }
    let parsed: [(GeofenceStation, Double)] = list.compactMap { j in
      guard let id = j["id"] as? String, let name = j["name"] as? String,
            let lat = j["lat"] as? Double, let lon = j["lon"] as? Double else { return nil }
      let d = (j["distance_m"] as? Double) ?? Double(j["distance_m"] as? Int ?? Int.max)
      return (GeofenceStation(id: id, name: name, lat: lat, lon: lon), d)
    }
    return parsed.sorted { $0.1 < $1.1 }.prefix(maxNearest).map { $0.0 }
  }
}

final class GeofenceManager: NSObject, CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
  static let shared = GeofenceManager()
  static let umbrellaId = "umbrella"
  static let stationPrefix = "station:"

  /// Set by the channel while a Flutter engine is alive.
  var onNudgeTapped: (([String: String]) -> Void)?

  private let manager = CLLocationManager(), defaults = UserDefaults.standard, center = UNUserNotificationCenter.current()
  private var lastEvent: String? {
    didSet { if let e = lastEvent { NSLog("[geofence] %@", e) } }
  }

  private enum Mode { case idle, configureFix, umbrellaFix, dwell(GeofenceStation) }
  private var mode = Mode.idle
  private var fixes: [CLLocation] = []
  private var modeTimer: Timer?
  private var bgTask = UIBackgroundTaskIdentifier.invalid
  private var configureReply: (([String: Any]) -> Void)?
  private var permissionReply: ((String) -> Void)?
  private var wantAlways = false

  private override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    manager.pausesLocationUpdatesAutomatically = false
    center.delegate = self
  }

  /// Called at launch. Without a stored config (fresh install, debug run before Dart configured) nothing happens.
  /// APNs tokens can rotate, so an authorised app re-registers on every launch.
  func start() {
    _ = config
    center.getNotificationSettings { s in
      guard s.authorizationStatus == .authorized || s.authorizationStatus == .provisional else { return }
      DispatchQueue.main.async {
        NSLog("[push] registering with APNs")
        UIApplication.shared.registerForRemoteNotifications()
      }
    }
  }

  // MARK: push token

  /// Dart's listener for a fresh APNs token (hex). Set by the channel.
  var onPushToken: ((String) -> Void)?
  private(set) var pushToken: String? {
    get { defaults.string(forKey: "push.token") }
    set { defaults.set(newValue, forKey: "push.token") }
  }

  func pushRegistrationFailed(_ reason: String) {
    lastEvent = "APNs registration failed: \(reason)"
  }

  func pushTokenArrived(_ hex: String) {
    pushToken = hex
    lastEvent = "push token \(hex.prefix(8))…"
    onPushToken?(hex)
  }

  /// Asks for notification permission and, when granted, registers with APNs. Replies with the grant.
  func registerPush(reply: @escaping (Bool) -> Void) {
    center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
      DispatchQueue.main.async {
        self?.lastEvent = granted ? "notifications granted, registering with APNs" : "notifications denied"
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        reply(granted)
      }
    }
  }

  private var config: GeofenceConfig? {
    get { defaults.data(forKey: "geofence.config").flatMap { try? JSONDecoder().decode(GeofenceConfig.self, from: $0) } }
    set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "geofence.config") }
  }
  private var nearest: [GeofenceStation] {
    get { defaults.data(forKey: "geofence.nearest").flatMap { try? JSONDecoder().decode([GeofenceStation].self, from: $0) } ?? [] }
    set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "geofence.nearest") }
  }
  private var pendingNudge: [String: String]? {
    get { defaults.dictionary(forKey: "geofence.pendingNudge") as? [String: String] }
    set { defaults.set(newValue, forKey: "geofence.pendingNudge") }
  }

  func configure(_ args: [String: Any], reply: @escaping ([String: Any]) -> Void) {
    let stations = (args["stations"] as? [[String: Any]] ?? []).compactMap { j -> GeofenceStation? in
      guard let id = j["id"] as? String, let name = j["name"] as? String,
            let lat = j["lat"] as? Double, let lon = j["lon"] as? Double else { return nil }
      return GeofenceStation(id: id, name: name, lat: lat, lon: lon)
    }
    let c = GeofenceConfig(
      apiUrl: args["apiUrl"] as? String ?? "", token: args["token"] as? String ?? "",
      enabled: args["enabled"] as? Bool ?? false, riding: args["riding"] as? Bool ?? false,
      stations: stations, umbrellaRadiusM: args["umbrellaRadiusM"] as? Double ?? 8000,
      stationRadiusM: args["stationRadiusM"] as? Double ?? 300,
      quietFrom: args["quietFrom"] as? String, quietTo: args["quietTo"] as? String)
    config = c
    stopAllRegions()
    guard c.enabled, CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
      reply(["registered": 0])
      return
    }
    let n = registerStations(c)
    lastEvent = "configure: \(n) stations, enabled=\(c.enabled), riding=\(c.riding), auth=\(Self.permissionString(authStatus))"
    configureReply = reply
    beginMode(.configureFix, timeout: 10) { [weak self] in self?.configureReply?(["registered": n]); self?.configureReply = nil }
    manager.requestLocation()
  }

  func requestPermission(always: Bool, reply: @escaping (String) -> Void) {
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
      if granted { DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() } }
    }
    let status = authStatus
    switch (status, always) {
    case (.notDetermined, _):
      permissionReply = reply
      wantAlways = always
      manager.requestWhenInUseAuthorization()
    case (.authorizedWhenInUse, true):
      permissionReply = reply
      manager.requestAlwaysAuthorization()
      // iOS may answer silently (provisional Always); do not keep Dart waiting.
      DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
        self?.permissionReply?(Self.permissionString(self?.authStatus ?? .denied))
        self?.permissionReply = nil
      }
    default:
      reply(Self.permissionString(status))
    }
  }

  func status(reply: @escaping ([String: Any]) -> Void) {
    center.getNotificationSettings { [self] s in
      var out: [String: Any] = [
        "permission": Self.permissionString(authStatus),
        "notifications": s.authorizationStatus == .authorized || s.authorizationStatus == .provisional,
        "registered": manager.monitoredRegions.count,
        "pushToken": pushToken as Any,
      ]
      if let e = lastEvent { out["lastEvent"] = e }
      if let p = pendingNudge {
        out["pendingNudge"] = p
        pendingNudge = nil
      }
      DispatchQueue.main.async { reply(out) }
    }
  }

  func stop() {
    stopAllRegions()
    endMode()
    nearest = []
    if var c = config { c.enabled = false; config = c }
  }

  /// Deployment target is iOS 13; the instance property arrived in iOS 14.
  private var authStatus: CLAuthorizationStatus {
    if #available(iOS 14, *) { return manager.authorizationStatus }
    return CLLocationManager.authorizationStatus()
  }

  static func permissionString(_ s: CLAuthorizationStatus) -> String {
    switch s {
    case .notDetermined: return "notDetermined"
    case .authorizedAlways: return "always"
    case .authorizedWhenInUse: return "whileInUse"
    default: return "denied"
    }
  }

  private func stopAllRegions() {
    for r in manager.monitoredRegions { manager.stopMonitoring(for: r) }
  }

  @discardableResult
  private func registerStations(_ c: GeofenceConfig) -> Int {
    let set = GeofenceRules.regionSet(frequent: c.stations, nearest: nearest)
    for s in set {
      let r = CLCircularRegion(center: s.location.coordinate, radius: c.stationRadiusM, identifier: Self.stationPrefix + s.id)
      r.notifyOnEntry = true
      r.notifyOnExit = true
      manager.startMonitoring(for: r)
      // iOS fires no entry event for a region the phone is already inside when
      // monitoring starts (typical right after an umbrella exit re-registers the
      // nearest stations). Ask; `didDetermineState` treats `.inside` like an entry.
      manager.requestState(for: r)
    }
    return set.count
  }

  private func registerUmbrella(at l: CLLocation, _ c: GeofenceConfig) {
    if let old = manager.monitoredRegions.first(where: { $0.identifier == Self.umbrellaId }) { manager.stopMonitoring(for: old) }
    let r = CLCircularRegion(center: l.coordinate, radius: c.umbrellaRadiusM, identifier: Self.umbrellaId)
    r.notifyOnEntry = false
    r.notifyOnExit = true
    manager.startMonitoring(for: r)
  }

  private func station(for region: CLRegion) -> GeofenceStation? {
    guard region.identifier.hasPrefix(Self.stationPrefix), let c = config else { return nil }
    let id = String(region.identifier.dropFirst(Self.stationPrefix.count))
    return (c.stations + nearest).first { $0.id == id }
  }

  private func beginMode(_ m: Mode, timeout: TimeInterval, onTimeout: @escaping () -> Void) {
    endMode()
    mode = m
    fixes = []
    bgTask = UIApplication.shared.beginBackgroundTask { [weak self] in
      guard let self = self else { return }
      // iOS grants ~30 s here. A dwell keeps running on the location background
      // mode (updates are active), so only the task is released; other modes end.
      if case .dwell = self.mode {
        if self.bgTask != .invalid { UIApplication.shared.endBackgroundTask(self.bgTask); self.bgTask = .invalid }
      } else {
        self.endMode()
      }
    }
    modeTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
      onTimeout()
      self?.endMode()
    }
  }

  private func endMode() {
    modeTimer?.invalidate(); modeTimer = nil
    if case .dwell = mode { manager.stopUpdatingLocation() }
    mode = .idle
    fixes = []
    if bgTask != .invalid {
      UIApplication.shared.endBackgroundTask(bgTask)
      bgTask = .invalid
    }
  }

  func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
    guard let reply = permissionReply, authStatus != .notDetermined else { return }
    if authStatus == .authorizedWhenInUse && wantAlways {
      // iOS shows the Always upgrade later on its own schedule; ask once, answer Dart now.
      wantAlways = false
      manager.requestAlwaysAuthorization()
    }
    permissionReply = nil
    reply(Self.permissionString(authStatus))
  }

  func locationManager(_ m: CLLocationManager, didEnterRegion region: CLRegion) {
    enteredStation(region)
  }

  func locationManager(_ m: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
    guard state == .inside, region.identifier.hasPrefix(Self.stationPrefix) else { return }
    if case .dwell = mode { return } // one dwell window at a time
    enteredStation(region)
  }

  /// Entry: the nudge is scheduled 60 s out and iOS delivers it on its own, so
  /// nothing depends on the app staying alive. Leaving the region, or a fix
  /// outside it or at vehicle speed during the short watch window, cancels it.
  private func enteredStation(_ region: CLRegion) {
    guard let c = config, c.enabled, let s = station(for: region) else { return }
    lastEvent = "enter \(s.name)"
    if c.riding { lastEvent = "riding, no nudge"; return }
    guard scheduleNudge(s, c) else { return }
    beginMode(.dwell(s), timeout: GeofenceRules.watchWindow) { [weak self] in self?.lastEvent = "watch over \(s.name), nudge stays scheduled" }
    manager.allowsBackgroundLocationUpdates = true
    manager.startUpdatingLocation()
  }

  private func cancelNudge(_ s: GeofenceStation, reason: String) {
    center.removePendingNotificationRequests(withIdentifiers: ["nudge-\(s.id)"])
    defaults.removeObject(forKey: "geofence.nudged.\(s.id)")
    lastEvent = "cancelled \(s.name): \(reason)"
  }

  func locationManager(_ m: CLLocationManager, didExitRegion region: CLRegion) {
    if let s = station(for: region) {
      if case .dwell(let d) = mode, d.id == s.id { endMode() }
      cancelNudge(s, reason: "left the region")
      return
    }
    guard region.identifier == Self.umbrellaId, let c = config, c.enabled else { return }
    lastEvent = "umbrella exit"
    beginMode(.umbrellaFix, timeout: 20) {}
    manager.requestLocation()
  }

  func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let l = locations.last, let c = config else { return }
    switch mode {
    case .configureFix:
      registerUmbrella(at: l, c)
      finishConfigure()
    case .umbrellaFix:
      endMode()
      refreshNearest(around: l, c)
    case .dwell(let s):
      lastEvent = "watch fix at \(Int(l.distance(from: s.location))) m, \(Int(max(l.speed, 0))) m/s"
      if GeofenceRules.fixCancelsNudge(l, station: s.location, radius: c.stationRadiusM) {
        endMode()
        cancelNudge(s, reason: "passing through")
      }
    case .idle: break
    }
  }

  func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
    switch mode {
    case .configureFix: finishConfigure()
    case .umbrellaFix: endMode()
    default: break
    }
  }

  private func finishConfigure() {
    let reply = configureReply
    configureReply = nil
    endMode()
    reply?(["registered": manager.monitoredRegions.count])
  }

  private func refreshNearest(around l: CLLocation, _ c: GeofenceConfig) {
    let task = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
    let finish = { [weak self] (found: [GeofenceStation]?) in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if let found = found, !found.isEmpty {
          self.nearest = found
          self.stopAllRegions()
          self.registerStations(c)
        }
        self.registerUmbrella(at: l, c)
        self.lastEvent = "umbrella recentred, nearest \(found?.count ?? 0)"
        if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
      }
    }
    guard var comps = URLComponents(string: c.apiUrl + "/v1/stations/nearby") else { return finish(nil) }
    comps.queryItems = [URLQueryItem(name: "lat", value: "\(l.coordinate.latitude)"), URLQueryItem(name: "lon", value: "\(l.coordinate.longitude)")]
    guard let url = comps.url else { return finish(nil) }
    var req = URLRequest(url: url, timeoutInterval: 10)
    req.setValue("Bearer \(c.token)", forHTTPHeaderField: "Authorization")
    URLSession.shared.dataTask(with: req) { data, resp, _ in
      guard let data = data, (resp as? HTTPURLResponse)?.statusCode == 200 else { return finish(nil) }
      finish(GeofenceRules.parseNearby(data))
    }.resume()
  }

  @discardableResult
  private func scheduleNudge(_ s: GeofenceStation, _ c: GeofenceConfig) -> Bool {
    let fireAt = Date().addingTimeInterval(GeofenceRules.nudgeDelay)
    if GeofenceRules.isQuiet(now: fireAt, from: c.quietFrom, to: c.quietTo) { lastEvent = "quiet \(s.name)"; return false }
    let key = "geofence.nudged.\(s.id)"
    if let last = defaults.object(forKey: key) as? Date, Date().timeIntervalSince(last) < GeofenceRules.nudgeCooldown {
      lastEvent = "cooldown \(s.name)"
      return false
    }
    defaults.set(Date(), forKey: key)
    lastEvent = "nudge scheduled \(s.name) in \(Int(GeofenceRules.nudgeDelay)) s"
    let content = UNMutableNotificationContent()
    content.title = "Am \(s.name)?"
    content.body = "Einchecken, bevor der Zug kommt."
    content.sound = .default
    content.threadIdentifier = "nudge"
    content.userInfo = ["stationId": s.id, "stationName": s.name]
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: GeofenceRules.nudgeDelay, repeats: false)
    center.add(UNNotificationRequest(identifier: "nudge-\(s.id)", content: content, trigger: trigger))
    return true
  }

  func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification, withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) {
    // In the foreground the Bahnsteig shows its own banner.
    if n.request.content.threadIdentifier == "nudge" { return h([]) }
    if #available(iOS 14, *) { h([.banner, .sound]) } else { h([.alert, .sound]) }
  }

  func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler h: @escaping () -> Void) {
    let info = r.notification.request.content.userInfo
    if let id = info["stationId"] as? String {
      let payload = ["stationId": id, "stationName": info["stationName"] as? String ?? ""]
      if let cb = onNudgeTapped { cb(payload) } else { pendingNudge = payload }
    }
    h()
  }
}
