import CoreLocation
import XCTest

@testable import Runner

class GeofenceRulesTests: XCTestCase {
  private func at(_ h: Int, _ m: Int) -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = 9; c.day = 10; c.hour = h; c.minute = m
    return Calendar.current.date(from: c)!
  }

  func testQuietHoursAcrossMidnight() {
    XCTAssertTrue(GeofenceRules.isQuiet(now: at(23, 30), from: "22:00", to: "06:00"))
    XCTAssertTrue(GeofenceRules.isQuiet(now: at(5, 59), from: "22:00", to: "06:00"))
    XCTAssertFalse(GeofenceRules.isQuiet(now: at(6, 0), from: "22:00", to: "06:00"))
    XCTAssertFalse(GeofenceRules.isQuiet(now: at(12, 0), from: "22:00", to: "06:00"))
    XCTAssertTrue(GeofenceRules.isQuiet(now: at(13, 0), from: "12:00", to: "14:00"))
    XCTAssertFalse(GeofenceRules.isQuiet(now: at(13, 0), from: nil, to: nil))
    XCTAssertFalse(GeofenceRules.isQuiet(now: at(13, 0), from: "12:00", to: "12:00"))
    XCTAssertFalse(GeofenceRules.isQuiet(now: at(13, 0), from: "25:00", to: "06:00"))
  }

  func testRegionSetCapsAndDedupes() {
    let frequent = (0..<20).map { GeofenceStation(id: "f\($0)", name: "F\($0)", lat: 50, lon: 7) }
    let nearest = [
      GeofenceStation(id: "f1", name: "F1", lat: 50, lon: 7),
      GeofenceStation(id: "n1", name: "N1", lat: 50, lon: 7),
      GeofenceStation(id: "n2", name: "N2", lat: 50, lon: 7),
      GeofenceStation(id: "n3", name: "N3", lat: 50, lon: 7),
      GeofenceStation(id: "n4", name: "N4", lat: 50, lon: 7),
    ]
    let set = GeofenceRules.regionSet(frequent: frequent, nearest: nearest)
    XCTAssertEqual(set.count, 19)
    XCTAssertEqual(set.prefix(16).map { $0.id }, (0..<16).map { "f\($0)" })
    XCTAssertEqual(set.suffix(3).map { $0.id }, ["n1", "n2", "n3"])
    XCTAssertEqual(Set(set.map { $0.id }).count, 19)
  }

  func testFixCancelsNudge() {
    let station = CLLocation(latitude: 50.9432, longitude: 6.9586)
    let inside = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 50.9440, longitude: 6.9586), altitude: 0, horizontalAccuracy: 30, verticalAccuracy: 0, course: 0, speed: 1, timestamp: Date())
    let outside = CLLocation(latitude: 50.9500, longitude: 6.9586)
    let fast = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 50.9440, longitude: 6.9586), altitude: 0, horizontalAccuracy: 30, verticalAccuracy: 0, course: 0, speed: 15, timestamp: Date())
    XCTAssertFalse(GeofenceRules.fixCancelsNudge(inside, station: station, radius: 300))
    XCTAssertTrue(GeofenceRules.fixCancelsNudge(outside, station: station, radius: 300))
    XCTAssertTrue(GeofenceRules.fixCancelsNudge(fast, station: station, radius: 300))
  }

  func testParseNearbyTakesThreeNearest() {
    let json = """
    {"stations":[{"id":"a","name":"A","lat":1,"lon":1,"distance_m":900},{"id":"b","name":"B","lat":1,"lon":1,"distance_m":100},
    {"id":"c","name":"C","lat":1,"lon":1,"distance_m":500},{"id":"d","name":"D","lat":1,"lon":1,"distance_m":300},{"id":"x","name":"X"}],
    "source":"gps","label":null}
    """.data(using: .utf8)!
    XCTAssertEqual(GeofenceRules.parseNearby(json).map { $0.id }, ["b", "d", "c"])
    XCTAssertEqual(GeofenceRules.parseNearby(Data("nope".utf8)), [])
  }
}
