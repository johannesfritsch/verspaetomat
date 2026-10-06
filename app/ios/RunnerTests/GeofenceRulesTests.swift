import CoreLocation
import XCTest

@testable import Runner

/// The pure rules behind station geofencing (docs/25). They are the part that decides how much
/// the phone talks to the backend on a long trip, so they are worth pinning down away from
/// CoreLocation.
final class GeofenceRulesTests: XCTestCase {

  /// docs/25 §1: the disc reaches as far as the passenger is travelling fast.
  func testCoverageRadiusFollowsSpeed() {
    // Standing, walking, a tram: be precise.
    XCTAssertEqual(GeofenceRules.coverageRadius(speedMps: 0), 5_000)
    XCTAssertEqual(GeofenceRules.coverageRadius(speedMps: 8), 5_000) // 28.8 km/h
    // A regional train: one refresh every few stops.
    XCTAssertEqual(GeofenceRules.coverageRadius(speedMps: 9), 25_000) // 32.4 km/h
    XCTAssertEqual(GeofenceRules.coverageRadius(speedMps: 33), 25_000) // 118.8 km/h
    // Long distance: one refresh per leg, not per field.
    XCTAssertEqual(GeofenceRules.coverageRadius(speedMps: 34), 60_000) // 122.4 km/h
    XCTAssertEqual(GeofenceRules.coverageRadius(speedMps: 80), 60_000)
    // A negative speed is CoreLocation saying "I don't know", not a direction.
    XCTAssertEqual(GeofenceRules.coverageRadius(speedMps: -1), 5_000)
  }

  /// Inside the disc nothing happens and no network call is made.
  func testDiscContainment() {
    let koeln = CLLocation(latitude: 50.9413, longitude: 6.9583)
    let duesseldorf = CLLocation(latitude: 51.2198, longitude: 6.7942)  // ~34 km away
    XCTAssertTrue(GeofenceRules.insideDisc(koeln, centre: koeln, radius: 5_000))
    XCTAssertFalse(GeofenceRules.insideDisc(duesseldorf, centre: koeln, radius: 5_000))
    XCTAssertFalse(GeofenceRules.insideDisc(duesseldorf, centre: koeln, radius: 25_000))
    XCTAssertTrue(GeofenceRules.insideDisc(duesseldorf, centre: koeln, radius: 60_000))
  }

  func testSpeedBetweenTwoFixes() {
    let t0 = Date()
    let a = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 50.9413, longitude: 6.9583),
                       altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: t0)
    // ~34 km in 20 minutes is a bit over 100 km/h.
    let b = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 51.2198, longitude: 6.7942),
                       altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: t0.addingTimeInterval(1200))
    let kmh = GeofenceRules.speedBetween(a, b) * 3.6
    XCTAssertGreaterThan(kmh, 90)
    XCTAssertLessThan(kmh, 120)
    // Two fixes at the same instant say nothing; they must not read as infinite speed.
    XCTAssertEqual(GeofenceRules.speedBetween(a, a), 0)
  }

  /// Issue #11: in Wangen two entries named the same platform — one from the frequent set, one
  /// from the nearby list — and the phone sat inside both circles, so it was nudged twice.
  func testOnePlatformIsOneRegion() {
    // Same spot, different feeds, different spelling and different ids.
    let a = GeofenceStation(id: "de:08436:12345", name: "Wangen (Allgäu)", lat: 47.6870, lon: 9.8330)
    let b = GeofenceStation(id: "mock:wangen-bahnhof", name: "Wangen (Allgäu) Bahnhof", lat: 47.6871, lon: 9.8332)
    XCTAssertTrue(GeofenceRules.samePlace(a, b))
    let set = GeofenceRules.regionSet(frequent: [a], nearest: [b], here: CLLocation(latitude: 47.687, longitude: 9.833))
    XCTAssertEqual(set.count, 1, "one platform, one circle")

    // A different station that happens to be close by keeps its own circle.
    let neighbour = GeofenceStation(id: "x", name: "Wangen Nord", lat: 47.6872, lon: 9.8331)
    XCTAssertFalse(GeofenceRules.samePlace(a, neighbour))
    // The same name 200 km away is a different station and stays one.
    let elsewhere = GeofenceStation(id: "y", name: "Wangen (Allgäu)", lat: 49.5, lon: 9.8)
    XCTAssertFalse(GeofenceRules.samePlace(a, elsewhere))
  }

  /// Köln Hbf and Köln Hauptbahnhof are one place; Köln Hbf and Köln Süd are not.
  func testNormaliseFoldsTheWordForTheThingItself() {
    XCTAssertEqual(GeofenceRules.normalise("Köln Hauptbahnhof"), GeofenceRules.normalise("Köln Hbf"))
    XCTAssertEqual(GeofenceRules.normalise("Kißlegg Bahnhof"), GeofenceRules.normalise("Kisslegg"))
    XCTAssertNotEqual(GeofenceRules.normalise("Köln Hbf"), GeofenceRules.normalise("Köln Süd"))
  }

  /// docs/25 §2: the budget follows the passenger over the 50 km boundary.
  func testRegionBudgetFollowsThePassenger() {
    let frequent = (0..<16).map { GeofenceStation(id: "f\($0)", name: "Frequent \($0)", lat: 50.94 + Double($0) / 1000, lon: 6.95) }
    let nearest = (0..<20).map { GeofenceStation(id: "n\($0)", name: "Nearest \($0)", lat: 48.0 + Double($0) / 1000, lon: 11.5) }

    // At home: the frequent set keeps its 15 slots, the nearest get 4. Nineteen, not twenty —
    // iOS takes twenty regions in total and the twentieth is the umbrella (issue #31).
    let atHome = CLLocation(latitude: 50.9413, longitude: 6.9583)
    let home = GeofenceRules.regionSet(frequent: frequent, nearest: nearest, here: atHome)
    XCTAssertEqual(home.count, GeofenceRules.maxRegions)
    XCTAssertEqual(home.count, 19, "the umbrella needs the twentieth slot")
    XCTAssertEqual(home.filter { $0.id.hasPrefix("f") }.count, 15)
    XCTAssertEqual(home.filter { $0.id.hasPrefix("n") }.count, 4)

    // 300 km away the frequent set buys nothing: every slot goes to what is actually here.
    let away = CLLocation(latitude: 48.1372, longitude: 11.5755) // München
    let far = GeofenceRules.regionSet(frequent: frequent, nearest: nearest, here: away)
    XCTAssertEqual(far.count, GeofenceRules.maxRegions)
    XCTAssertTrue(far.allSatisfy { $0.id.hasPrefix("n") })

    // Not knowing where the phone is, the frequent set is the better guess: it is at least
    // somewhere this person has stood.
    XCTAssertTrue(GeofenceRules.nearHome(frequent: frequent, here: nil))
    // Just inside and just outside the boundary, measured due north of Köln.
    let just = CLLocation(latitude: 50.9413 + 0.40, longitude: 6.9583)   // ~44 km
    let past = CLLocation(latitude: 50.9413 + 0.55, longitude: 6.9583)   // ~61 km
    XCTAssertTrue(GeofenceRules.nearHome(frequent: frequent, here: just))
    XCTAssertFalse(GeofenceRules.nearHome(frequent: frequent, here: past))
    // No frequent stations at all (a fresh account) is never "near home".
    XCTAssertFalse(GeofenceRules.nearHome(frequent: [], here: atHome))
  }

  /// issue #31: how wide the umbrella is, and the one thing that may widen it.
  ///
  /// The failure this guards is specific and has already happened three times: an answer with
  /// nothing in it being read as "there is nothing out here", which draws a huge circle around a
  /// wrong answer and means the phone does not ask again until it has travelled that far.
  func testUmbrellaOnlyWidensOnAPositiveAnswer() {
    let here = CLLocation(latitude: 47.7914, longitude: 9.8921) // Kißlegg
    let watched = GeofenceStation(id: "a", name: "Kißlegg Bahnhof", lat: 47.7936, lon: 9.8820)
    // ~12 km east, and not registered.
    let unwatched = GeofenceStation(id: "b", name: "Wangen", lat: 47.6836, lon: 9.8319)

    // A complete answer sizes the umbrella from the nearest station we are NOT watching.
    let complete = GeofenceRules.NearbyAnswer(
      stations: [watched, unwatched], searchedRadius: 25_000, complete: true)
    let sized = GeofenceRules.umbrellaRadius(
      registered: [watched], answer: complete, here: here,
      stationRadius: 300, cautious: 8_000, deviceMax: 100_000)
    let toUnwatched = here.distance(from: unwatched.location)
    XCTAssertEqual(sized.radius, toUnwatched - 300 - GeofenceRules.margin, accuracy: 1)
    XCTAssertTrue(sized.why.contains("unwatched"), sized.why)

    // An EMPTY answer must not widen anything, however far it claims to have searched. This is
    // the self-sealing loop of issue #31, and it is the whole reason `complete` exists.
    let empty = GeofenceRules.NearbyAnswer(stations: [], searchedRadius: 40_000, complete: false)
    XCTAssertEqual(
      GeofenceRules.umbrellaRadius(
        registered: [], answer: empty, here: here,
        stationRadius: 300, cautious: 8_000, deviceMax: 100_000).radius,
      8_000,
      "an absence is not evidence of emptiness")

    // An old server says nothing at all: cautious, exactly as before this change.
    let silent = GeofenceRules.NearbyAnswer(stations: [watched], searchedRadius: 0, complete: false)
    XCTAssertEqual(
      GeofenceRules.umbrellaRadius(
        registered: [watched], answer: silent, here: here,
        stationRadius: 300, cautious: 8_000, deviceMax: 100_000).radius,
      8_000)
  }

  /// Nothing unregistered inside a complete answer means the reach is the answer's own radius —
  /// the Allgäu case, where a wide umbrella is correct because there is genuinely nothing to miss.
  func testEmptyCountrysideGetsAWideUmbrella() {
    let here = CLLocation(latitude: 47.79, longitude: 9.89)
    let only = GeofenceStation(id: "a", name: "Kißlegg", lat: 47.7936, lon: 9.8820)
    let answer = GeofenceRules.NearbyAnswer(stations: [only], searchedRadius: 40_000, complete: true)
    let sized = GeofenceRules.umbrellaRadius(
      registered: [only], answer: answer, here: here,
      stationRadius: 300, cautious: 8_000, deviceMax: 100_000)
    XCTAssertEqual(sized.radius, 40_000 - GeofenceRules.margin, accuracy: 1)
    XCTAssertTrue(sized.why.contains("nothing unregistered"), sized.why)
  }

  /// A radius iOS will not monitor is worse than a smaller one: the region is refused outright and
  /// the mechanism everything hangs off is silently absent.
  func testTheDeviceCeilingBinds() {
    let here = CLLocation(latitude: 47.79, longitude: 9.89)
    let only = GeofenceStation(id: "a", name: "Kißlegg", lat: 47.7936, lon: 9.8820)
    let answer = GeofenceRules.NearbyAnswer(stations: [only], searchedRadius: 90_000, complete: true)
    let sized = GeofenceRules.umbrellaRadius(
      registered: [only], answer: answer, here: here,
      stationRadius: 300, cautious: 8_000, deviceMax: 10_000)
    XCTAssertEqual(sized.radius, 9_000, accuracy: 1, "0.9 of what the device will take")
    XCTAssertTrue(sized.why.contains("clamped"), sized.why)

    // A station practically underfoot would give a negative radius; a circle that small is not
    // delivered at all, so there is a floor.
    let underfoot = GeofenceStation(id: "b", name: "Hier", lat: 47.7901, lon: 9.8901)
    let tight = GeofenceRules.NearbyAnswer(stations: [underfoot], searchedRadius: 25_000, complete: true)
    XCTAssertEqual(
      GeofenceRules.umbrellaRadius(
        registered: [], answer: tight, here: here,
        stationRadius: 300, cautious: 8_000, deviceMax: 100_000).radius,
      GeofenceRules.minRadius)
  }

  /// docs/25 §3: exit is the honest signal. Rolling into a station and stopping used to cancel
  /// a nudge that should have fired, because the speed at that moment still looked like a train.
  func testOnlyLeavingTheRegionCancelsTheNudge() {
    let station = CLLocation(latitude: 50.9413, longitude: 6.9583)
    let onThePlatform = CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 50.9414, longitude: 6.9584),
      altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: Date())
    XCTAssertFalse(GeofenceRules.fixCancelsNudge(onThePlatform, station: station, radius: 300))
    let downTheLine = CLLocation(latitude: 50.9600, longitude: 6.9583)
    XCTAssertTrue(GeofenceRules.fixCancelsNudge(downTheLine, station: station, radius: 300))
  }

  /// docs/25 §4: nobody should be nudged forever by an app they stopped using.
  func testSwitchOffThresholds() {
    XCTAssertEqual(GeofenceRules.ignoresBeforeMute, 3)
    XCTAssertEqual(GeofenceRules.stationMuteDays, 30)
    XCTAssertEqual(GeofenceRules.idleDaysBeforeOff, 30)
  }
}

/// The region plan with premises on (issue #64, docs/48).
final class PremiseRegionTests: XCTestCase {
  private func st(_ n: Int) -> GeofenceStation { GeofenceStation(id: "vs:\(n)", name: "S\(n)", lat: 50 + Double(n) * 0.01, lon: 7) }
  private let ring = PremiseCircle(lat: 50.5, lon: 7.5, radius: 450)
  private func entry(_ touches: Int) -> PremiseEntry {
    PremiseEntry(ring: ring, touch: (0..<touches).map { PremiseCircle(lat: 50.5 + Double($0) * 0.001, lon: 7.5, radius: 130) })
  }

  func testAStationWithAPremiseIsWatchedByItsRingAndOneWithoutBy300m() {
    let specs = GeofenceRules.premiseRegions(set: [st(1), st(2)], stays: [], premise: { $0 == "vs:1" ? self.entry(3) : nil }, stationRadius: 300)
    XCTAssertEqual(specs.map(\.id), ["station:vs:1", "station:vs:2"])
    XCTAssertEqual(specs[0].radius, 450)
    XCTAssertEqual(specs[0].lat, 50.5)
    XCTAssertEqual(specs[1].radius, 300)
    XCTAssertTrue(specs.allSatisfy { $0.entry && $0.exit })
  }

  /// A stay adds its touch points, keeps its own ring whatever the set says, and what no longer
  /// fits beside the touch points is cut from the end of the set — never the stay, never past 19.
  func testAStayKeepsItsRingAndMakesRoomForItsTouchPoints() {
    let set = (1...19).map(st)
    let stay = PremiseStay(station: st(42), entry: entry(6), enteredAt: Date(), nudged: false)
    let specs = GeofenceRules.premiseRegions(set: set, stays: [stay], premise: { _ in nil }, stationRadius: 300)
    XCTAssertEqual(specs.count, 19)
    XCTAssertEqual(specs.first?.id, "station:vs:42")
    XCTAssertEqual(specs.first?.radius, 450, "the stay's own ring, not the 300 m of a station without premise")
    let touch = specs.filter { $0.id.hasPrefix("touch:") }
    XCTAssertEqual(touch.map(\.id), (1...6).map { "touch:vs:42:\($0)" })
    XCTAssertTrue(touch.allSatisfy { $0.entry && !$0.exit })
    XCTAssertFalse(specs.contains { $0.id == "station:vs:19" }, "the least important station made room")
  }

  func testTwoStaysFitBesideTheUmbrella() {
    let stays = [42, 43].map { PremiseStay(station: st($0), entry: entry(6), enteredAt: Date(), nudged: false) }
    let specs = GeofenceRules.premiseRegions(set: (1...19).map(st), stays: stays, premise: { _ in nil }, stationRadius: 300)
    XCTAssertEqual(specs.count, 19)
    XCTAssertEqual(specs.filter { $0.id.hasPrefix("touch:") }.count, 12)
    XCTAssertTrue(specs.contains { $0.id == "station:vs:42" } && specs.contains { $0.id == "station:vs:43" })
  }

  func testATouchPointNamesItsStation() {
    XCTAssertEqual(GeofenceRules.stationId(ofTouch: "touch:vs:17:2"), "vs:17")
    XCTAssertEqual(GeofenceRules.stationId(ofTouch: "touch:de-DELFI_de:05315:11201:1"), "de-DELFI_de:05315:11201")
    XCTAssertNil(GeofenceRules.stationId(ofTouch: "station:vs:17"))
  }

  /// #86: a station nudge that lands while the app is open is swallowed, and nobody saw it.
  func testOnlyAStationNudgeIsSwallowedInTheOpenApp() {
    XCTAssertEqual(GeofenceRules.swallowedNudgeStation(thread: "nudge", userInfo: ["stationId": "vs:4711", "stationName": "St. Ingbert"]), "vs:4711")
    // The test notification of the Entwicklung page is meant to be seen, and a server push has its banner.
    XCTAssertNil(GeofenceRules.swallowedNudgeStation(thread: "test", userInfo: [:]))
    XCTAssertNil(GeofenceRules.swallowedNudgeStation(thread: "", userInfo: ["verspaetomat": ["kind": "journey"]]))
    // Swallowed, but there is no station whose tally it could have moved.
    XCTAssertNil(GeofenceRules.swallowedNudgeStation(thread: "nudge", userInfo: [:]))
    XCTAssertNil(GeofenceRules.swallowedNudgeStation(thread: "nudge", userInfo: ["stationId": ""]))
  }

  /// #86, docs/25 §4: `scheduleNudge` counts a nudge as unanswered when it plans it. One the open
  /// app swallowed was never seen, so it was never ignored either: the count it added goes back.
  func testASwallowedNudgeIsNotCountedAsIgnored() {
    XCTAssertEqual(GeofenceRules.ignoredAfterSwallowed(1), 0, "the only one: the station has no tally left")
    XCTAssertEqual(GeofenceRules.ignoredAfterSwallowed(3), 2, "three in the open app is not a month of quiet")
    // A tap or a check-in cleared the tally between scheduling and firing: nothing to take back.
    XCTAssertEqual(GeofenceRules.ignoredAfterSwallowed(0), 0)
  }
}
