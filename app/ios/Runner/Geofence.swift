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
  /// How long the phone must stay in a region before the nudge fires (docs/25 §3). Tunable from
  /// the debug page so it can be settled on real trips rather than argued about.
  var nudgeDelay: TimeInterval = GeofenceRules.defaultNudgeDelay
  /// How close the phone has to actually be before the nudge is scheduled (issue #8, docs/35).
  var nudgeRadiusM: Double = GeofenceRules.defaultNudgeRadius
}

/// Pure rules, kept free of CoreLocation state so they can be unit-tested.
enum GeofenceRules {
  /// The region budget (docs/25 §2). iOS allows 20 monitored regions. The frequent set is worth
  /// its slots at home and worthless 300 km away, so it is spent on whichever matters here.
  static let maxRegions = 20
  static let maxFrequent = 16
  static let nearestNearHome = 4
  /// Beyond this from every frequent station, the frequent set is dropped and all 20 slots go
  /// to what is actually around the passenger.
  static let awayFromHomeM: CLLocationDistance = 50_000

  /// The nudge fires only if the phone is still in the region three minutes later (docs/25 §3):
  /// a train passing through is long gone by then, a passenger on a platform is not. Exit
  /// cancels it, which is the honest signal — the old 25 s speed watch guessed at the same
  /// thing and cancelled real arrivals.
  static let defaultNudgeDelay: TimeInterval = 180
  static let nudgeCooldown: TimeInterval = 30 * 60

  /// While one nudge stands, no second one is scheduled — a neighbouring platform is the same
  /// spot as far as a passenger is concerned (issue #11).
  static let oneNudgeWindow: TimeInterval = 10 * 60

  /// „Am Bahnhof" should mean standing at it, not walking past its outskirts (issue #8). The
  /// monitored region stays wide because iOS delivers small circles late or not at all — a 50 m
  /// region is monitored from cell towers like any other and simply misses. So the region is the
  /// wake-up and this is the nudge: after entering, the app watches its own fixes and schedules
  /// only once one lands this close to the station.
  static let defaultNudgeRadius: CLLocationDistance = 50

  /// How long that watch runs. Walking in from the edge of a 300 m circle takes about three
  /// minutes; beyond this the phone is near the station but not going to it, and the watch —
  /// the only part of this that costs battery — gives up.
  static let nearWatchWindow: TimeInterval = 6 * 60

  /// Once the phone is that close, the nudge is a short hop out: far enough that a train rolling
  /// through cancels itself by leaving the region, near enough to be useful on a platform.
  static let nearNudgeDelay: TimeInterval = 45

  /// How far the coverage disc reaches, by how fast the phone is moving (docs/25 §1). Drawn
  /// around somewhere the passenger recently *was*, so a München → Memmingen trip costs two or
  /// three `stations/nearby` calls instead of about twenty.
  static func coverageRadius(speedMps: CLLocationSpeed) -> CLLocationDistance {
    let kmh = max(0, speedMps) * 3.6
    if kmh < 30 { return 5_000 }      // walking or local: be precise
    if kmh <= 120 { return 25_000 }   // a regional train: one refresh every few stops
    return 60_000                     // long distance: one refresh per leg, not per field
  }

  /// Inside the disc nothing happens and no network call is made.
  static func insideDisc(_ fix: CLLocation, centre: CLLocation, radius: CLLocationDistance) -> Bool {
    fix.distance(from: centre) <= radius
  }

  /// Speed between two fixes, in m/s. `CLLocation.speed` is -1 when the OS has none, and
  /// significant-location updates usually do not carry one, so it is measured rather than read.
  static func speedBetween(_ a: CLLocation, _ b: CLLocation) -> CLLocationSpeed {
    let seconds = b.timestamp.timeIntervalSince(a.timestamp)
    guard seconds > 1 else { return 0 }
    return b.distance(from: a) / seconds
  }

  /// A nudge ignored this many times running mutes its station for 30 days (docs/25 §4).
  static let ignoresBeforeMute = 3
  static let stationMuteDays = 30
  /// No check-in for this long switches background scanning off altogether.
  static let idleDaysBeforeOff = 30

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

  /// The region set, spent on whoever is nearby (docs/25 §2). Within [`awayFromHomeM`] of any
  /// frequent station the passenger is somewhere they live: 16 frequent plus 4 nearest. Beyond
  /// it the frequent set buys nothing, so all 20 slots go to the nearest stations.
  ///
  /// `here` nil means we do not know where the phone is; the frequent set is then the better
  /// guess, because it is at least somewhere this person has actually stood.
  static func regionSet(frequent: [GeofenceStation], nearest: [GeofenceStation], here: CLLocation?) -> [GeofenceStation] {
    var out: [GeofenceStation] = []
    // Same spot, two entries: the frequent set and the nearby list name one platform differently
    // often enough (docs/30), and two circles around it meant two nudges in Wangen (issue #11).
    // Ids alone do not catch it; the name and 250 m do.
    func known(_ s: GeofenceStation) -> Bool {
      out.contains { $0.id == s.id || samePlace($0, s) }
    }
    if nearHome(frequent: frequent, here: here) {
      for s in frequent where !known(s) && out.count < maxFrequent { out.append(s) }
      var added = 0
      for s in nearest where !known(s) && added < nearestNearHome {
        out.append(s)
        added += 1
      }
      return out
    }
    for s in nearest where !known(s) && out.count < maxRegions { out.append(s) }
    return out
  }

  /// One platform under two names: close together, and one name is the other plus the word for
  /// the thing itself (`Bahnhof`, `Bf`, `Hbf`) — the Swift half of Dart's `sameStation`.
  static func samePlace(_ a: GeofenceStation, _ b: GeofenceStation) -> Bool {
    guard a.location.distance(from: b.location) <= 250 else { return false }
    let x = normalise(a.name), y = normalise(b.name)
    if x.isEmpty || y.isEmpty { return false }
    return x == y || x.hasPrefix(y) || y.hasPrefix(x)
  }

  static func normalise(_ name: String) -> String {
    var s = name.lowercased()
      .replacingOccurrences(of: "hauptbahnhof", with: "hbf")
      .folding(options: .diacriticInsensitive, locale: .current)
    s = String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    for suffix in ["bahnhof", "hbf", "bf"] where s.hasSuffix(suffix) && s.count > suffix.count {
      s = String(s.dropLast(suffix.count))
      break
    }
    return s
  }

  /// Within [`awayFromHomeM`] of any frequent station. Unknown position counts as near home.
  static func nearHome(frequent: [GeofenceStation], here: CLLocation?) -> Bool {
    guard let here = here else { return true }
    if frequent.isEmpty { return false }
    return frequent.contains { $0.location.distance(from: here) <= awayFromHomeM }
  }

  /// A fix that proves the phone is not standing at the station: outside the radius. The speed
  /// test went with docs/25 §3 — rolling in and stopping used to cancel a nudge that should
  /// have fired, and exit already says the honest thing.
  static func fixCancelsNudge(_ fix: CLLocation, station: CLLocation, radius: Double) -> Bool {
    fix.distance(from: station) > radius
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
    return parsed.sorted { $0.1 < $1.1 }.prefix(maxRegions).map { $0.0 }
  }
}

final class GeofenceManager: NSObject, CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
  static let shared = GeofenceManager()
  static let umbrellaId = "umbrella"

  /// The nudge's own category, so it can carry the "Ruhe" action (docs/24 §3): the pause is
  /// wanted at exactly the moment the notification arrives, not three screens away.
  static let nudgeCategory = "station-nudge"
  static let snoozeAction = "nudge-snooze"
  static let stationPrefix = "station:"

  /// When the last nudge was scheduled, whichever station it was for (issue #11).
  static let pendingKey = "geofence.nudge.pending"

  /// Set by the channel while a Flutter engine is alive.
  var onNudgeTapped: (([String: String]) -> Void)?

  /// The umbrella was left and the station set re-registered around the new position. Dart
  /// listens so a card backgrounded across half of Germany resolves again (docs/24 §0).
  var onUmbrellaExit: (() -> Void)?

  private let manager = CLLocationManager(), defaults = UserDefaults.standard, center = UNUserNotificationCenter.current()
  private var lastEvent: String? {
    didSet { if let e = lastEvent { NSLog("[geofence] %@", e); appendLog(e) } }
  }

  // -- The log (docs/25 §5) --------------------------------------------------
  //
  // Nearly everything interesting here happens while the app is suspended, so the buffer is
  // written natively and persisted; Dart reads it through the channel and merges its own lines
  // in. It holds paths, not bodies, and no claim content — and nothing leaves the phone by
  // itself. A ring of the last 500 entries, which is a long trip's worth.

  static let logCap = 500
  private let logKey = "geofence.log"

  private func appendLog(_ text: String) {
    var lines = defaults.stringArray(forKey: logKey) ?? []
    let stamp = ISO8601DateFormatter().string(from: Date())
    lines.append("\(stamp)\tgeofence\t\(text)")
    if lines.count > Self.logCap { lines.removeFirst(lines.count - Self.logCap) }
    defaults.set(lines, forKey: logKey)
  }

  func readLog() -> [String] { defaults.stringArray(forKey: logKey) ?? [] }

  func clearLog() { defaults.removeObject(forKey: logKey) }

  // -- Counters since midnight (docs/25 §5) ---------------------------------
  //
  // So "why no nudge at Memmingen?" can be answered from the phone, and so the expected-traffic
  // table in the doc is falsifiable on a real trip rather than argued about.

  private var countersDay: String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
  }

  func bumpCounter(_ name: String) {
    let key = "geofence.count.\(countersDay).\(name)"
    defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
  }

  func counters() -> [String: Int] {
    var out: [String: Int] = [:]
    let prefix = "geofence.count.\(countersDay)."
    for (k, v) in defaults.dictionaryRepresentation() where k.hasPrefix(prefix) {
      if let n = v as? Int { out[String(k.dropFirst(prefix.count))] = n }
    }
    return out
  }

  private enum Mode { case idle, configureFix, umbrellaFix, dwell(GeofenceStation) }
  private var mode = Mode.idle
  private var fixes: [CLLocation] = []

  // -- The coverage disc (docs/25 §1) ---------------------------------------
  //
  // Where the station set was last drawn around, and how far it reaches. A significant-location
  // update inside the disc costs nothing at all; outside it, one `stations/nearby` re-centres
  // everything. The radius follows how fast the phone is moving, so a long-distance leg is one
  // refresh rather than one per field.

  private var discCentre: CLLocation? {
    get {
      guard let lat = defaults.object(forKey: "geofence.disc.lat") as? Double,
            let lon = defaults.object(forKey: "geofence.disc.lon") as? Double else { return nil }
      return CLLocation(latitude: lat, longitude: lon)
    }
    set {
      guard let n = newValue else {
        defaults.removeObject(forKey: "geofence.disc.lat")
        defaults.removeObject(forKey: "geofence.disc.lon")
        return
      }
      defaults.set(n.coordinate.latitude, forKey: "geofence.disc.lat")
      defaults.set(n.coordinate.longitude, forKey: "geofence.disc.lon")
      defaults.set(Date(), forKey: "geofence.disc.at")
    }
  }

  private var discRadius: CLLocationDistance {
    get { defaults.object(forKey: "geofence.disc.r") as? Double ?? GeofenceRules.coverageRadius(speedMps: 0) }
    set { defaults.set(newValue, forKey: "geofence.disc.r") }
  }

  private var discAt: Date? { defaults.object(forKey: "geofence.disc.at") as? Date }

  /// The last significant-location fix, so the next one can be turned into a speed.
  private var lastSignificant: CLLocation?

  // -- Nudges nobody acts on (docs/25 §4) -----------------------------------
  //
  // Three in a row at the same station — not tapped, no check-in within half an hour — and that
  // station goes quiet for thirty days. Counted natively, because the whole point is that the
  // app is not running. Dart reads the tally through `status` and folds it into the muted list,
  // which already carries an expiry.

  private func ignoreKey(_ id: String) -> String { "geofence.ignored.\(id)" }

  private func noteNudgeFired(_ s: GeofenceStation) {
    let n = defaults.integer(forKey: ignoreKey(s.id)) + 1
    defaults.set(n, forKey: ignoreKey(s.id))
    if n >= GeofenceRules.ignoresBeforeMute {
      lastEvent = "\(s.name) ignored \(n)× — due to be muted for \(GeofenceRules.stationMuteDays) days"
    }
  }

  /// A tap, or a check-in: this station is being used after all, so the tally starts over.
  func clearIgnored(_ stationId: String) {
    defaults.removeObject(forKey: ignoreKey(stationId))
  }

  /// Stations whose nudges have gone unanswered often enough to be muted, with how often.
  func ignoredTally() -> [String: Int] {
    var out: [String: Int] = [:]
    for (k, v) in defaults.dictionaryRepresentation() where k.hasPrefix("geofence.ignored.") {
      if let n = v as? Int, n >= GeofenceRules.ignoresBeforeMute {
        out[String(k.dropFirst("geofence.ignored.".count))] = n
      }
    }
    return out
  }
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
        if granted {
          UIApplication.shared.registerForRemoteNotifications()
          self?.registerNudgeCategory()
        }
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
      quietFrom: args["quietFrom"] as? String, quietTo: args["quietTo"] as? String,
      nudgeDelay: args["nudgeDelayS"] as? Double ?? GeofenceRules.defaultNudgeDelay,
      nudgeRadiusM: args["nudgeRadiusM"] as? Double ?? GeofenceRules.defaultNudgeRadius)
    config = c
    // A journey that started while a nudge was already pending used to let it fire anyway: the
    // notification lives in iOS, not in the app, and nothing took it back (issue #11). The same
    // for a switched-off layer.
    if c.riding || !c.enabled {
      cancelAllNudges(reason: c.riding ? "riding" : "off")
    }
    stopAllRegions()
    guard c.enabled, CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
      manager.stopMonitoringSignificantLocationChanges()
      discCentre = nil
      reply(["registered": 0])
      return
    }
    startCoarseLayer()
    let n = registerStations(c)
    lastEvent = "configure: \(n) stations, enabled=\(c.enabled), riding=\(c.riding), auth=\(Self.permissionString(authStatus))"
    configureReply = reply
    registerNudgeCategory()
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
        // docs/25 §4: stations whose nudges nobody answered, for Dart to mute with an expiry.
        "ignored": ignoredTally(),
        // docs/25 §5: the coverage disc, so the debug page can say why nothing happened.
        "discLat": discCentre?.coordinate.latitude as Any,
        "discLon": discCentre?.coordinate.longitude as Any,
        "discRadiusM": discRadius,
        "discAt": discAt?.timeIntervalSince1970 as Any,
        "counters": counters(),
        // Every registered region, with whether the phone is inside it right now (docs/25 §5).
        "regions": manager.monitoredRegions.compactMap { r -> [String: Any]? in
          guard let c = r as? CLCircularRegion else { return nil }
          var row: [String: Any] = ["id": c.identifier, "lat": c.center.latitude, "lon": c.center.longitude, "radiusM": c.radius]
          if let here = discCentre {
            row["distanceM"] = here.distance(from: CLLocation(latitude: c.center.latitude, longitude: c.center.longitude))
            row["inside"] = c.contains(here.coordinate)
          }
          if let st = station(for: c) { row["name"] = st.name }
          return row
        },
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
    let set = GeofenceRules.regionSet(frequent: c.stations, nearest: nearest, here: discCentre)
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

  /// The coarse "where am I roughly" trigger (docs/25 §1). Significant location changes cost
  /// almost nothing, arrive from cell towers at most every few minutes, and relaunch a
  /// terminated app — and they free the 20th region slot the umbrella used to hold. The umbrella
  /// stays only as a backstop for devices where they are unavailable.
  private func startCoarseLayer() {
    if CLLocationManager.significantLocationChangeMonitoringAvailable() {
      manager.startMonitoringSignificantLocationChanges()
      lastEvent = "significant-location monitoring on"
    } else {
      lastEvent = "no significant-location monitoring; umbrella is the backstop"
    }
  }

  /// A significant-location update. Inside the disc this is free; outside it costs one
  /// `stations/nearby` and re-centres everything around where the passenger actually is.
  private func significantUpdate(_ l: CLLocation, _ c: GeofenceConfig) {
    let speed = lastSignificant.map { GeofenceRules.speedBetween($0, l) } ?? 0
    lastSignificant = l
    if let centre = discCentre, GeofenceRules.insideDisc(l, centre: centre, radius: discRadius) {
      lastEvent = "inside the disc, nothing to do"
      return
    }
    discRadius = GeofenceRules.coverageRadius(speedMps: speed)
    lastEvent = "left the disc at \(Int(speed * 3.6)) km/h, radius now \(Int(discRadius / 1000)) km"
    refreshNearest(around: l, c)
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
    if case .dwell = mode {
      manager.stopUpdatingLocation()
      manager.allowsBackgroundLocationUpdates = false
      manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
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

  /// Entry: the nudge is scheduled three minutes out and iOS delivers it on its own, so nothing
  /// depends on the app staying alive (docs/25 §3). A train passing through has left the region
  /// long before it fires, and the exit cancels it. Nothing else watches: the old 25 s
  /// vehicle-speed window was a guess at the same thing and cancelled real arrivals.
  private func enteredStation(_ region: CLRegion) {
    guard let c = config, c.enabled, let s = station(for: region) else { return }
    // `didDetermineState` reports every monitored region at once after a configure, and the
    // phone is usually inside more than one of them. Without this, one configure writes a dozen
    // enter/cooldown pairs and a few of those flush the log ring of everything worth reading
    // (docs/25 §5). A station already inside its cooldown has nothing new to say.
    if inCooldown(s) { return }
    lastEvent = "enter \(s.name)"
    if c.riding { lastEvent = "riding, no nudge"; return }
    beginNearWatch(s, c)
  }

  /// The region was entered; now find out whether the passenger is actually *at* the station
  /// (issue #8, docs/35). The app turns its own fixes on for a few minutes and schedules the
  /// nudge on the first one inside [GeofenceConfig.nudgeRadiusM]. No fix that close, no nudge —
  /// walking past the edge of the region stays silent.
  private func beginNearWatch(_ s: GeofenceStation, _ c: GeofenceConfig) {
    if case .dwell = mode { return } // one watch at a time
    manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    manager.allowsBackgroundLocationUpdates = true
    manager.startUpdatingLocation()
    lastEvent = "watching for \(Int(c.nudgeRadiusM)) m at \(s.name)"
    beginMode(.dwell(s), timeout: GeofenceRules.nearWatchWindow) { [weak self] in
      self?.lastEvent = "no fix within \(Int(c.nudgeRadiusM)) m of \(s.name)"
    }
  }

  private func inCooldown(_ s: GeofenceStation) -> Bool {
    guard let last = defaults.object(forKey: "geofence.nudged.\(s.id)") as? Date else { return false }
    return Date().timeIntervalSince(last) < GeofenceRules.nudgeCooldown
  }

  private func cancelNudge(_ s: GeofenceStation, reason: String) {
    bumpCounter("cancelled")
    center.removePendingNotificationRequests(withIdentifiers: ["nudge-\(s.id)"])
    defaults.removeObject(forKey: "geofence.nudged.\(s.id)")
    defaults.removeObject(forKey: Self.pendingKey)
    lastEvent = "cancelled \(s.name): \(reason)"
  }

  /// Every nudge that has not been delivered yet, gone. Used when a journey starts and when the
  /// layer is switched off (issue #11).
  private func cancelAllNudges(reason: String) {
    center.getPendingNotificationRequests { [weak self] requests in
      let ids = requests.map { $0.identifier }.filter { $0.hasPrefix("nudge-") }
      guard !ids.isEmpty else { return }
      self?.center.removePendingNotificationRequests(withIdentifiers: ids)
      DispatchQueue.main.async {
        self?.bumpCounter("cancelled")
        self?.lastEvent = "cancelled \(ids.count) pending: \(reason)"
      }
    }
    defaults.removeObject(forKey: Self.pendingKey)
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
      // The first fix of a configure draws the disc and the region set around where we are.
      discCentre = l
      discRadius = GeofenceRules.coverageRadius(speedMps: 0)
      registerStations(c)
      finishConfigure()
    case .umbrellaFix:
      endMode()
      refreshNearest(around: l, c)
    case .dwell(let s):
      // Close enough: this is the nudge (issue #8). A fix outside the wide region is an exit we
      // can act on early; the speed test went with docs/25 §3.
      let metres = l.distance(from: s.location)
      if metres <= c.nudgeRadiusM {
        endMode()
        lastEvent = "\(Int(metres)) m from \(s.name)"
        scheduleNudge(s, c, delay: GeofenceRules.nearNudgeDelay)
      } else if GeofenceRules.fixCancelsNudge(l, station: s.location, radius: c.stationRadiusM) {
        endMode()
        lastEvent = "left \(s.name) before getting close"
      }
    case .idle:
      // Not waiting for anything: this is the significant-location stream (docs/25 §1).
      significantUpdate(l, c)
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
        self.discCentre = l
        self.lastEvent = "recentred on \(Int(self.discRadius / 1000)) km disc, nearest \(found?.count ?? 0)"
        self.onUmbrellaExit?()
        if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
      }
    }
    bumpCounter("nearby")
    bumpCounter("requests")
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
  private func scheduleNudge(_ s: GeofenceStation, _ c: GeofenceConfig, delay: TimeInterval? = nil) -> Bool {
    let delay = delay ?? config?.nudgeDelay ?? GeofenceRules.defaultNudgeDelay
    let fireAt = Date().addingTimeInterval(delay)
    if GeofenceRules.isQuiet(now: fireAt, from: c.quietFrom, to: c.quietTo) { lastEvent = "quiet \(s.name)"; return false }
    if inCooldown(s) {
      lastEvent = "cooldown \(s.name)"
      return false
    }
    // Two stations at one spot (a Bahnhof and its Haltestelle, one in the frequent set and one
    // from the nearby list) both report "inside" after a configure and both used to nudge. One
    // nudge stands at a time; the second station has nothing to add (issue #11).
    if let pending = defaults.object(forKey: Self.pendingKey) as? Date, Date().timeIntervalSince(pending) < GeofenceRules.oneNudgeWindow {
      lastEvent = "another nudge already stands, not \(s.name)"
      return false
    }
    defaults.set(Date(), forKey: "geofence.nudged.\(s.id)")
    defaults.set(Date(), forKey: Self.pendingKey)
    lastEvent = "nudge scheduled \(s.name) in \(Int(delay)) s"
    let content = UNMutableNotificationContent()
    content.title = "Am \(s.name)?"
    content.body = "Einchecken, bevor der Zug kommt."
    content.sound = .default
    content.threadIdentifier = "nudge"
    content.categoryIdentifier = Self.nudgeCategory
    content.userInfo = ["stationId": s.id, "stationName": s.name]
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
    center.add(UNNotificationRequest(identifier: "nudge-\(s.id)", content: content, trigger: trigger))
    bumpCounter("scheduled")
    // Counted as unanswered from the moment it is scheduled; a tap or a check-in clears it.
    noteNudgeFired(s)
    return true
  }

  /// Registers the nudge's action set. Cheap and idempotent; called alongside the permission
  /// request and on every configure, so an app updated into docs/24 gets it without a reinstall.
  func registerNudgeCategory() {
    let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "3 Stunden Ruhe", options: [])
    let category = UNNotificationCategory(identifier: Self.nudgeCategory, actions: [snooze], intentIdentifiers: [], options: [])
    center.setNotificationCategories([category])
  }

  func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification, withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) {
    // In the foreground the Bahnsteig shows its own banner.
    if n.request.content.threadIdentifier == "nudge" { bumpCounter("fired"); return h([]) }
    if #available(iOS 14, *) { h([.banner, .sound]) } else { h([.alert, .sound]) }
  }

  func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler h: @escaping () -> Void) {
    let info = r.notification.request.content.userInfo
    // "3 Stunden Ruhe" straight from the notification (docs/24 §3). Dart owns the account, so
    // it does the patch; the app is launched into the background for it if it is not running.
    if r.actionIdentifier == Self.snoozeAction {
      let payload = ["kind": "snooze", "hours": "3"]
      if let cb = onNudgeTapped { cb(payload) } else { pendingNudge = payload }
      return h()
    }
    var payload: [String: String]? = nil
    if let id = info["stationId"] as? String {
      clearIgnored(id) // acted on, so it was never ignored (docs/25 §4)
      payload = ["kind": "station", "stationId": id, "stationName": info["stationName"] as? String ?? ""]
    } else if let v = info["verspaetomat"] as? [String: Any], let kind = v["kind"] as? String {
      // A server push (docs/17): kind "journey" with {journey_id, transfer|arrived}, "mail", "incident", …
      let data = v["data"] as? [String: Any] ?? [:]
      var p = ["kind": kind]
      for (k, val) in data {
        if let str = val as? String { p[k] = str } else if let b = val as? Bool { p[k] = b ? "true" : "false" } else if let n = val as? NSNumber { p[k] = n.stringValue }
      }
      payload = p
    }
    if let payload = payload {
      if let cb = onNudgeTapped { cb(payload) } else { pendingNudge = payload }
    }
    h()
  }
}
