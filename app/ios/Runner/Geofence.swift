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
  /// Nineteen stations plus the umbrella: iOS takes twenty in total, and the one it refuses when
  /// the set is full must never be the umbrella every other trigger hangs off.
  static let maxRegions = 19
  static let maxFrequent = 15
  static let nearestNearHome = 4
  /// Beyond this from every frequent station, the frequent set is dropped and all 20 slots go
  /// to what is actually around the passenger.
  static let awayFromHomeM: CLLocationDistance = 50_000

  /// How far the phone may be from where the nearby list was fetched before that list is treated
  /// as describing somewhere else (issue #31). Wider than a station circle so a walk across town
  /// does not re-ask, far narrower than the coverage disc so a different town always does.
  static let nearestStaleM: CLLocationDistance = 3_000

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
  /// How wide the umbrella should be, given what the server just said (issue #31).
  ///
  /// The umbrella's job is to fire before the phone can *stop* at a station nobody registered. So
  /// its radius is the distance to the nearest station we did **not** register, less the station
  /// circle, less what the phone travels while iOS is deciding to tell us.
  ///
  /// Three things this deliberately does not do:
  ///
  /// - **It never widens on an absence.** Only `complete` — the server positively asserting it
  ///   searched `searchedRadius` and found everything in it — may take the radius past
  ///   `cautiousRadius`. An empty answer is what a failed lookup, a thin timetable and a bad
  ///   deploy all look like, and widening on that is how issue #31 sealed itself shut.
  /// - **It uses an absolute margin, not a percentage.** Exit delivery takes minutes, not metres:
  ///   a tenth of a 1.5 km city umbrella is 150 m, and a walker covers 400 m before iOS speaks.
  ///   A percentage gives the most margin exactly where it is least needed.
  /// - **It does not promise what the platform cannot.** At line speed the phone can be twenty
  ///   kilometres past the boundary before the exit arrives, so "you cannot *reach* an
  ///   unregistered station" is not achievable. What holds is: you cannot *stop* at one without
  ///   a refresh having been triggered — and stopping is the only case a nudge needs.
  static func umbrellaRadius(
    registered: [GeofenceStation],
    answer: NearbyAnswer,
    here: CLLocation,
    stationRadius: CLLocationDistance,
    cautious: CLLocationDistance,
    deviceMax: CLLocationDistance
  ) -> (radius: CLLocationDistance, why: String) {
    let ceiling = deviceMax > 0 ? min(deviceMax * 0.9, 200_000) : 200_000

    func clamped(_ r: CLLocationDistance, _ why: String) -> (CLLocationDistance, String) {
      let out = max(minRadius, min(r, ceiling))
      return (out, out == ceiling && r > ceiling ? "\(why), clamped to device max" : why)
    }

    guard answer.complete else {
      return clamped(cautious, "server did not claim a complete answer")
    }

    // The nearest station the server named that we are not watching. Beyond the answer's own
    // reach we know nothing, so the search radius is the honest ceiling on this claim.
    let registeredIds = Set(registered.map { $0.id })
    let firstUnregistered = answer.stations
      .filter { !registeredIds.contains($0.id) }
      .map { here.distance(from: $0.location) }
      .min()

    guard let d = firstUnregistered else {
      return clamped(answer.searchedRadius - margin, "nothing unregistered within \(Int(answer.searchedRadius / 1000)) km")
    }
    return clamped(d - stationRadius - margin, "nearest unwatched station \(Int(d / 1000)) km off")
  }

  /// What the phone covers while iOS makes up its mind about an exit. Absolute, because the
  /// latency is a time and the distance it costs depends on speed, not on how big the circle is.
  static let margin: CLLocationDistance = 1_000

  /// How many stations to ask for. Enough that there is normally one we do not register, which is
  /// the quantity the umbrella is sized from; the phone can watch nineteen.
  static let nearbyLimit = 25

  /// Below this a circle is not reliably delivered at all, so there is no point drawing one.
  static let minRadius: CLLocationDistance = 1_000

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
      // `maxRegions` binds here too. Fifteen plus four is nineteen, but the guard is on the total
      // rather than on the arithmetic, so changing either constant cannot quietly hand iOS a
      // twentieth region and cost us the umbrella.
      for s in nearest where !known(s) && added < nearestNearHome && out.count < maxRegions {
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
      // ß is a letter, not an accent, so `diacriticInsensitive` leaves it alone — and the feeds
      // disagree about it: DELFI writes „Kißlegg", the Swiss feed writes „Kisslegg". Without this
      // the two are different places, which is two regions on one platform and the double nudge
      // docs/30 was supposed to have ended. A test has asserted this since docs/30 and has been
      // failing ever since, because nothing runs the Swift tests.
      .replacingOccurrences(of: "ß", with: "ss")
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
  /// What `stations/nearby` answered, with the scope it answered within (issue #31).
  struct NearbyAnswer {
    var stations: [GeofenceStation] = []
    /// How far the server looked. Zero when it did not say — an older build, or the gazetteer path.
    var searchedRadius: CLLocationDistance = 0
    /// The server asserts every station within `searchedRadius` is in `stations`. Only this may
    /// let the umbrella grow past the cautious default.
    var complete: Bool = false
  }

  static func parseNearbyAnswer(_ data: Data) -> NearbyAnswer {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return NearbyAnswer()
    }
    return NearbyAnswer(
      stations: parseNearby(data),
      searchedRadius: (root["search_radius_m"] as? Double) ?? Double(root["search_radius_m"] as? Int ?? 0),
      complete: root["complete"] as? Bool ?? false)
  }

  static func parseNearby(_ data: Data) -> [GeofenceStation] {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let list = root["stations"] as? [[String: Any]] else { return [] }
    let parsed: [(GeofenceStation, Double)] = list.compactMap { j in
      guard let id = j["id"] as? String, let name = j["name"] as? String,
            let lat = j["lat"] as? Double, let lon = j["lon"] as? Double else { return nil }
      let d = (j["distance_m"] as? Double) ?? Double(j["distance_m"] as? Int ?? Int.max)
      return (GeofenceStation(id: id, name: name, lat: lat, lon: lon), d)
    }
    // NOT cut to `maxRegions`. The umbrella is sized from the nearest station we do *not*
    // register, so the list has to be longer than the set — cutting it here made that station
    // invisible, `firstUnregistered` always nil, and the radius always the search radius instead
    // of the distance the rule was written to use. `regionSet` does the cutting.
    return parsed.sorted { $0.1 < $1.1 }.map { $0.0 }
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
    didSet {
      if let e = lastEvent {
        NSLog("[geofence] %@", e)
        appendLog(e)
        // When the layer was last alive at all. A log that simply stops says nothing on its own:
        // it looks the same whether iOS delivered no events, the app was force-quit, or the log
        // was cleared. This turns that silence into a fact the page can state.
        defaults.set(Date(), forKey: "geofence.lastEvent.at")
      }
    }
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

  // -- The two actions docs/25 §5 promised and nobody built (issue #29) ------
  //
  // Both exist so the fence can be tested where it runs — on a platform, on a real phone, from a
  // shipped build — instead of being reasoned about from a laptop. Neither writes anything to
  // the server: one asks a question that is already asked automatically, the other posts a
  // notification to this phone.

  /// Re-runs the lookup and redraws the region set around a fresh fix, now.
  ///
  /// This is the umbrella-exit path called by hand — the same one line for one behaviour, so
  /// tapping the button exercises what actually happens on a journey rather than a copy of it.
  ///
  /// It refuses rather than interrupts. `beginMode` would overwrite whatever mode is running,
  /// and the one that matters is `.dwell`: the phone is at a station with high-accuracy updates
  /// on, waiting for a fix inside the nudge radius. Replacing that loses the nudge it was about
  /// to schedule *and* leaves `stopUpdatingLocation` uncalled, so the GPS stays on at full
  /// accuracy until something else ends the mode. A diagnostics button must not be able to do
  /// that to the feature it exists to diagnose.
  ///
  /// Returns what happened, for the screen to say plainly.
  func refreshNow() -> String {
    guard authStatus == .authorizedAlways || authStatus == .authorizedWhenInUse else {
      lastEvent = "refresh asked for, but there is no location permission"
      return "denied"
    }
    guard let c = config, c.enabled else {
      lastEvent = "refresh asked for, but scanning is off"
      return "off"
    }
    if case .idle = mode {} else {
      lastEvent = "refresh asked for while busy, left alone"
      return "busy"
    }
    lastEvent = "refresh asked for by hand"
    beginMode(.umbrellaFix, timeout: 20) { [weak self] in
      // Without this the button is a promise nobody keeps: the fix never arrives, the mode times
      // out, and the log says only that a refresh was asked for.
      self?.lastEvent = "refresh got no fix in 20 s"
    }
    manager.requestLocation()
    return "started"
  }

  /// Posts a notification to this phone in `delay` seconds, and nothing else.
  ///
  /// It answers the one question the status rows cannot: does a notification from this app
  /// actually arrive on this phone, with the screen locked, right now. It deliberately does not
  /// go through `scheduleNudge`: no cooldown is written, no station is marked as nudged, no
  /// counter moves, and its payload is empty — so tapping it opens the app and does nothing,
  /// and it can never be mistaken for, or turn into, a real check-in.
  ///
  /// The reply waits for `UNUserNotificationCenter`, because the whole value of the button is
  /// that it reports the truth: on a phone where notifications are denied, `add` fails, and
  /// saying "scheduled" there would be the exact false negative it exists to rule out.
  func testNudge(delay: TimeInterval, reply: @escaping (Bool) -> Void) {
    let content = UNMutableNotificationContent()
    content.title = "Testhinweis"
    content.body = "Wenn du das siehst, kommen Hinweise auf diesem Telefon an."
    content.sound = .default
    // Not "nudge": that thread is swallowed in the foreground by `willPresent`, and the whole
    // point of this one is to be seen.
    content.threadIdentifier = "test"
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
    center.add(UNNotificationRequest(identifier: "test-nudge", content: content, trigger: trigger)) { [weak self] error in
      DispatchQueue.main.async {
        if let error = error {
          self?.lastEvent = "test notification refused: \(error.localizedDescription)"
          reply(false)
        } else {
          self?.lastEvent = "test notification in \(Int(delay)) s"
          reply(true)
        }
      }
    }
  }

  // -- Counters since midnight (docs/25 §5) ---------------------------------
  //
  // So "why no nudge at Memmingen?" can be answered from the phone, and so the expected-traffic
  // table in the doc is falsifiable on a real trip rather than argued about.

  /// `yyyy-MM-dd`, always Gregorian and always Latin digits.
  ///
  /// A bare `DateFormatter` follows the device's calendar and numbering, so on a phone set to a
  /// Buddhist or Japanese calendar the keys come out as another year entirely, and Dart — which
  /// builds the same string from `DateTime` arithmetic — stops matching them. Pinning the locale
  /// makes the key mean one thing on every phone.
  private static let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = Calendar(identifier: .gregorian)
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  private var countersDay: String { Self.dayFormatter.string(from: Date()) }

  func bumpCounter(_ name: String) {
    let key = "geofence.count.\(countersDay).\(name)"
    defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
  }

  func counters() -> [String: Int] {
    countersFor(day: countersDay)
  }

  private func countersFor(day: String) -> [String: Int] {
    var out: [String: Int] = [:]
    let prefix = "geofence.count.\(day)."
    for (k, v) in defaults.dictionaryRepresentation() where k.hasPrefix(prefix) {
      if let n = v as? Int { out[String(k.dropFirst(prefix.count))] = n }
    }
    return out
  }

  /// The counters of the days before today, newest first (issue #29).
  ///
  /// `bumpCounter` has always written one key per day and nothing has ever deleted them, so a
  /// week of real traffic is already on the phone — it was simply unreachable, because
  /// `counters()` only ever read today's prefix. This reads the rest back, which is the only
  /// honest history the app has: no position was ever recorded, but how often it asked, nudged
  /// and cancelled was.
  func countersHistory(days: Int) -> [[String: Any]] {
    var out: [[String: Any]] = []
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    for back in 0..<max(1, days) {
      guard let d = cal.date(byAdding: .day, value: -back, to: Date()) else { continue }
      let day = Self.dayFormatter.string(from: d)
      let c = countersFor(day: day)
      if c.isEmpty { continue }
      out.append(["day": day, "counters": c])
    }
    return out
  }

  private enum Mode { case idle, configureFix, umbrellaFix, dwell(GeofenceStation) }
  private var mode = Mode.idle

  /// What the layer is waiting for, in one word for the debug page (issue #31). „dwell" is the
  /// one that matters: the phone is at a station with the GPS on, deciding whether to nudge.
  private var modeLabel: String {
    switch mode {
    case .idle: return "idle"
    case .configureFix: return "configureFix"
    case .umbrellaFix: return "umbrellaFix"
    case .dwell(let s): return "dwell:\(s.name)"
    }
  }
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
    // The only thing left that the speed table decides: what the reach is before anything has
    // been registered at all. From the first `registerUmbrella` onwards the umbrella owns it.
    get { defaults.object(forKey: "geofence.disc.r") as? Double ?? GeofenceRules.coverageRadius(speedMps: 0) }
    set { defaults.set(newValue, forKey: "geofence.disc.r") }
  }

  private var discAt: Date? { defaults.object(forKey: "geofence.disc.at") as? Date }

  // -- What the debug page could not answer (issue #31) -----------------------
  //
  // The disc's timestamp was the only date describing this layer, and it is the wrong one:
  // `configure` moves the disc to wherever its fix lands while re-registering the station set it
  // already had, because the nearest list is only ever written by `refreshNearest`. So the page
  // could say „Gesetzt: gerade eben" above a set of stations drawn thirteen kilometres away, and
  // there was no way to see the difference. These record the set and the lookup in their own
  // right, so the two can visibly disagree.

  /// When the station set was last handed to iOS, and around which centre.
  private var regionsAt: Date? { defaults.object(forKey: "geofence.regions.at") as? Date }
  private var regionsCentre: CLLocation? {
    guard let lat = defaults.object(forKey: "geofence.regions.lat") as? Double,
          let lon = defaults.object(forKey: "geofence.regions.lon") as? Double else { return nil }
    return CLLocation(latitude: lat, longitude: lon)
  }

  private func noteRegionsDrawn(around centre: CLLocation?) {
    defaults.set(Date(), forKey: "geofence.regions.at")
    if let c = centre {
      defaults.set(c.coordinate.latitude, forKey: "geofence.regions.lat")
      defaults.set(c.coordinate.longitude, forKey: "geofence.regions.lon")
    } else {
      defaults.removeObject(forKey: "geofence.regions.lat")
      defaults.removeObject(forKey: "geofence.regions.lon")
    }
  }

  /// When the nearby list behind that set was last fetched, and how many stations came back.
  /// This is the one that goes stale without anything on screen changing.
  private var nearestAt: Date? { defaults.object(forKey: "geofence.nearest.at") as? Date }
  private var nearestCount: Int { defaults.integer(forKey: "geofence.nearest.n") }

  /// Where the nearby list was fetched. Without it a list is only dated, and a list from the
  /// right time in the wrong town looks exactly like a good one (issue #31).
  /// The umbrella's radius, computed from the last complete answer and persisted so a relaunch
  /// redraws the same circle instead of falling back to the cautious default (issue #31).
  private var umbrellaRadius: CLLocationDistance {
    get { defaults.object(forKey: "geofence.umbrella.r") as? Double ?? 0 }
    set { defaults.set(newValue, forKey: "geofence.umbrella.r") }
  }

  /// Why the umbrella is the size it is, kept so the page can say it without reading the log.
  private var umbrellaWhy: String? {
    get { defaults.string(forKey: "geofence.umbrella.why") }
    set { defaults.set(newValue, forKey: "geofence.umbrella.why") }
  }

  private var nearestCentre: CLLocation? {
    guard let lat = defaults.object(forKey: "geofence.nearest.lat") as? Double,
          let lon = defaults.object(forKey: "geofence.nearest.lon") as? Double else { return nil }
    return CLLocation(latitude: lat, longitude: lon)
  }

  /// Whether the stored nearby list still describes where the phone is.
  ///
  /// **This is the hole that kept Langenargen registered in Kißlegg.** `nearest` is persisted, and
  /// the only thing that ever writes it is `refreshNearest` — which runs on an umbrella exit, a
  /// disc exit, or the button. Standing still, none of those can fire: the umbrella and the disc
  /// are both centred on the phone. So a list fetched in one town survived every relaunch in
  /// another, and `configure` re-registered it each time without ever asking again.
  private func nearestFits(_ fix: CLLocation) -> Bool {
    guard let centre = nearestCentre, nearestAt != nil else { return false }
    return fix.distance(from: centre) <= GeofenceRules.nearestStaleM
  }

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
    // `stopAllRegions` just took the umbrella down, and the fix that puts it back may be ten
    // seconds away — or never, if `requestLocation` times out indoors or in a tunnel. Until it
    // lands there would be no umbrella at all, and the umbrella is the one trigger that brings
    // the layer back to life: without it nothing fires however far the phone travels. Put it
    // back now around the last place we knew, and let the fix re-centre it.
    if let centre = discCentre {
      registerUmbrella(at: centre, c)
    }
    // `n` is what got registered, not what Dart sent — those differ whenever the nearby list is
    // carrying the set, and reading it as "Dart sent one station" sent me down the wrong path.
    lastEvent = "configure: sent \(c.stations.count) frequent, registered \(n) regions, "
      + "enabled=\(c.enabled), riding=\(c.riding), auth=\(Self.permissionString(authStatus))"
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
        // issue #31: the set and the lookup, dated in their own right, and what the layer is
        // doing right now. Without these the page could only show the disc's timestamp, which
        // describes something else entirely.
        "regionsAt": regionsAt?.timeIntervalSince1970 as Any,
        "regionsLat": regionsCentre?.coordinate.latitude as Any,
        "regionsLon": regionsCentre?.coordinate.longitude as Any,
        "nearestAt": nearestAt?.timeIntervalSince1970 as Any,
        "nearestCount": nearestCount,
        "nearestLat": nearestCentre?.coordinate.latitude as Any,
        "nearestLon": nearestCentre?.coordinate.longitude as Any,
        // Nobody has ever read this off a real phone, and the umbrella is now sized against it.
        "maxRegionRadiusM": manager.maximumRegionMonitoringDistance,
        "umbrellaRadiusM": umbrellaRadius > 0 ? umbrellaRadius : (config?.umbrellaRadiusM ?? 0),
        // Whether that number was worked out from an answer or is just the fallback. Printing
        // only the metres cannot tell "computed 8 km" from "never computed, so 8 km" — and that
        // is exactly the question that could not be answered from the page.
        "umbrellaComputed": umbrellaRadius > 0,
        "umbrellaWhy": umbrellaWhy as Any,
        "mode": modeLabel,
        "lastEventAt": (defaults.object(forKey: "geofence.lastEvent.at") as? Date)?.timeIntervalSince1970 as Any,
        // Whether the one region that wakes everything else is actually being monitored. Its
        // absence is the quietest failure this layer has: the stations stay registered, the page
        // still looks populated, and nothing ever re-evaluates again.
        "umbrellaUp": manager.monitoredRegions.contains { $0.identifier == Self.umbrellaId },
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
    noteRegionsDrawn(around: discCentre)
    // The line that says why the set is what it is (issue #31). Reading it out of the pieces took
    // two rounds: „1 registriert" and a station thirty kilometres away is only explicable once you
    // know there were no frequent stations, no nearest ones, and which budget was in force.
    // Naming them is the point: „→ 1 stations" was true in Kißlegg for three builds running, and
    // the one station was Langenargen, thirty kilometres away. The count never said which.
    let named = set.isEmpty ? "none" : set.map { $0.name }.joined(separator: ", ")
    lastEvent = "regionSet: \(c.stations.count) frequent + \(nearest.count) nearest, "
      + "nearHome=\(GeofenceRules.nearHome(frequent: c.stations, here: discCentre)) → \(set.count): \(named)"
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
    // The radius belongs to the umbrella and is recomputed by the lookup below. Setting it from
    // speed here only changed it for the moment in between, and made this line report a number
    // that was never used. The speed itself is still worth saying — it is how a log reads back as
    // a journey.
    lastEvent = "left the \(Int(discRadius / 1000)) km disc at \(Int(speed * 3.6)) km/h"
    refreshNearest(around: l, c)
  }

  private func registerUmbrella(at l: CLLocation, _ c: GeofenceConfig) {
    if let old = manager.monitoredRegions.first(where: { $0.identifier == Self.umbrellaId }) { manager.stopMonitoring(for: old) }
    // The computed radius when there is one, otherwise the cautious default from the config —
    // which is what a fresh install, an old server and a failed lookup all get (issue #31).
    let radius = umbrellaRadius > 0 ? umbrellaRadius : c.umbrellaRadiusM
    let r = CLCircularRegion(center: l.coordinate, radius: radius, identifier: Self.umbrellaId)
    r.notifyOnEntry = false
    r.notifyOnExit = true
    manager.startMonitoring(for: r)
    // The disc and the umbrella were two notions of the same reach that could disagree: the
    // umbrella-exit path never consulted the disc, so on iOS the 8 km circle quietly overrode the
    // 25/60 km speed table on every journey. One radius now, used by both.
    discRadius = radius
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
      // The first fix of a configure draws the disc and the region set around where we are. The
      // radius is NOT set here: `registerUmbrella` has just set it to the umbrella's, and writing
      // the speed table's value over it put the two back out of step on every single launch —
      // the very thing merging them was supposed to end.
      discCentre = l
      registerStations(c)
      finishConfigure()
      // …and asks again if the list it just drew from belongs to somewhere else. Every other
      // path to `refreshNearest` needs the phone to *move*; standing still, the umbrella and the
      // disc are both centred on it and neither can fire. Without this a list fetched in one town
      // outlives every relaunch in the next one, which is exactly what happened in Kißlegg.
      if !nearestFits(l) {
        let how = nearestCentre.map { "\(Int($0.distance(from: l) / 1000)) km away" } ?? "never fetched"
        lastEvent = "nearest belongs elsewhere (\(how)), asking again"
        refreshNearest(around: l, c)
      }
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

  /// A region iOS refused to monitor (issue #29).
  ///
  /// Without this the refusal is silent: `startMonitoring` returns nothing, the region is simply
  /// absent from `monitoredRegions`, and the debug page shows a set that looks complete. The
  /// usual cause is the hard cap of 20 regions per app, which `regionSet` plus the umbrella can
  /// reach. Nothing is retried here — the line exists so the absence can be seen rather than
  /// guessed at.
  func locationManager(_ m: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
    let who = region.map { station(for: $0)?.name ?? $0.identifier } ?? "unknown region"
    lastEvent = "iOS refused \(who): \(Self.reason(for: error))"
    bumpCounter("refused")
  }

  /// Apple's sentence for a `CLError`, in three words instead of thirty.
  ///
  /// `localizedDescription` for every one of these is "The operation couldn't be completed.
  /// (kCLErrorDomain error 4.)" — the same string whatever went wrong, with the one informative
  /// part at the end. Five of those in a row filled a screen of the log and said nothing; the
  /// code is the whole message, so it is the whole message here.
  static func reason(for error: Error) -> String {
    guard let code = CLError.Code(rawValue: (error as NSError).code) else {
      return error.localizedDescription
    }
    switch code {
    case .denied: return "location denied"
    case .network: return "no network"
    case .regionMonitoringDenied: return "region monitoring denied (needs Always)"
    case .regionMonitoringFailure: return "region rejected — too many, too small, or too big"
    case .regionMonitoringSetupDelayed: return "setup delayed"
    case .regionMonitoringResponseDelayed: return "response delayed, region replaced"
    default: return "CLError \(code.rawValue)"
    }
  }

  private func finishConfigure() {
    let reply = configureReply
    configureReply = nil
    endMode()
    reply?(["registered": manager.monitoredRegions.count])
  }

  /// The lookup after leaving the umbrella, and what to do with each of its three answers.
  ///
  /// The distinction below is the whole of issue #31. The old code treated "the request failed"
  /// and "the answer was empty" the same: keep the stations we have. But it moved the disc and
  /// the umbrella to the new fix either way, which makes the state **self-sealing** — the
  /// umbrella is now centred where you are standing, so nothing fires again until you travel
  /// another eight kilometres, and each time it does the same thing happens. Johannes' log shows
  /// an hour of `umbrella exit` → `recentred …, nearest 0` while the registered station stayed a
  /// town away, and nothing on the phone said why.
  ///
  /// So: a *failed* request changes nothing but the disc — it is transient and the old set is
  /// still the best guess. An *empty* one is an answer: there is no station near here, the old
  /// nearest list describes somewhere else, and keeping it registered is worse than dropping it.
  private func refreshNearest(around l: CLLocation, _ c: GeofenceConfig) {
    let task = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
    let finish = { [weak self] (answer: GeofenceRules.NearbyAnswer?) in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if let answer = answer {
          self.defaults.set(Date(), forKey: "geofence.nearest.at")
          self.defaults.set(answer.stations.count, forKey: "geofence.nearest.n")
          self.defaults.set(l.coordinate.latitude, forKey: "geofence.nearest.lat")
          self.defaults.set(l.coordinate.longitude, forKey: "geofence.nearest.lon")
          self.nearest = answer.stations
          self.stopAllRegions()
          // The umbrella goes on FIRST. It used to be registered after the stations, so under the
          // twenty-region cap the one iOS refused was the umbrella itself — the mechanism every
          // other trigger hangs off. That never bit only because the server capped the inputs.
          let sized = GeofenceRules.umbrellaRadius(
            registered: GeofenceRules.regionSet(frequent: c.stations, nearest: answer.stations, here: l),
            answer: answer,
            here: l,
            stationRadius: c.stationRadiusM,
            cautious: c.umbrellaRadiusM,
            deviceMax: self.manager.maximumRegionMonitoringDistance)
          self.umbrellaRadius = sized.radius
          self.umbrellaWhy = sized.why
          self.registerUmbrella(at: l, c)
          self.registerStations(c)
          self.lastEvent = "umbrella \(Int(sized.radius / 1000)) km: \(sized.why)"
        } else {
          // A failed lookup keeps the set and the radius; only the centre follows the phone, so it
          // is not pinned to a boundary it keeps re-crossing.
          self.registerUmbrella(at: l, c)
        }
        self.discCentre = l
        let outcome = answer == nil
          ? "lookup failed, set untouched"
          : "nearest \(answer!.stations.count)\(answer!.complete ? ", complete" : ", not exhaustive")"
        self.lastEvent = "recentred on \(Int(self.discRadius / 1000)) km disc, \(outcome)"
        self.onUmbrellaExit?()
        if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
      }
    }
    bumpCounter("nearby")
    bumpCounter("requests")
    guard var comps = URLComponents(string: c.apiUrl + "/v1/stations/nearby") else { return finish(nil) }
    comps.queryItems = [
      URLQueryItem(name: "lat", value: "\(l.coordinate.latitude)"),
      URLQueryItem(name: "lon", value: "\(l.coordinate.longitude)"),
      // More than the three the Bahnsteig wants: the umbrella is sized from the nearest station
      // we do *not* register, so there has to be one to see.
      URLQueryItem(name: "limit", value: "\(GeofenceRules.nearbyLimit)"),
    ]
    guard let url = comps.url else { return finish(nil) }
    var req = URLRequest(url: url, timeoutInterval: 10)
    req.setValue("Bearer \(c.token)", forHTTPHeaderField: "Authorization")
    URLSession.shared.dataTask(with: req) { data, resp, _ in
      guard let data = data, (resp as? HTTPURLResponse)?.statusCode == 200 else { return finish(nil) }
      finish(GeofenceRules.parseNearbyAnswer(data))
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
