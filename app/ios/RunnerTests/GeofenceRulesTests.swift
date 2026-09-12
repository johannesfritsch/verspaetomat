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

    // At home: the frequent set keeps its 16 slots, the nearest get the other 4.
    let atHome = CLLocation(latitude: 50.9413, longitude: 6.9583)
    let home = GeofenceRules.regionSet(frequent: frequent, nearest: nearest, here: atHome)
    XCTAssertEqual(home.count, GeofenceRules.maxRegions)
    XCTAssertEqual(home.filter { $0.id.hasPrefix("f") }.count, 16)
    XCTAssertEqual(home.filter { $0.id.hasPrefix("n") }.count, 4)

    // 300 km away the frequent set buys nothing: all 20 slots go to what is actually here.
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
