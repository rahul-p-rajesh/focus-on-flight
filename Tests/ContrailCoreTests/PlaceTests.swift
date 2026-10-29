import Foundation
import Testing
@testable import ContrailCore

func sampleIndex() -> AirportIndex {
    AirportIndex(airports: [
        Airport(name: "London Heathrow Airport", code: "LHR", city: "London", coordinate: Coordinate(latitude: 51.47, longitude: -0.4543), size: 2),
        Airport(name: "London Gatwick Airport", code: "LGW", city: "London", coordinate: Coordinate(latitude: 51.1481, longitude: -0.1903), size: 2),
        Airport(name: "Manchester Airport", code: "MAN", city: "Manchester", coordinate: Coordinate(latitude: 53.3537, longitude: -2.275), size: 2),
        Airport(name: "Édimbourg Test Field", code: "EDT", city: "Édimbourg", coordinate: Coordinate(latitude: 55.95, longitude: -3.37), size: 0),
        Airport(name: "Fiji Nadi", code: "NAN", city: "Nadi", coordinate: Coordinate(latitude: -17.75, longitude: 177.44), size: 2),
        Airport(name: "Samoa Faleolo", code: "APW", city: "Apia", coordinate: Coordinate(latitude: -13.83, longitude: -172.0), size: 1),
    ])
}

@Suite struct AirportIndexTests {
    let idx = sampleIndex()

    @Test func nearestSnaps() {
        let near = Coordinate(latitude: 51.5, longitude: -0.5)
        #expect(idx.nearest(near, withinKm: AirportIndex.snapRadiusKm)?.airport.code == "LHR")
        #expect(idx.nearest(Coordinate(latitude: 0, longitude: 0), withinKm: 30) == nil)
    }

    @Test func nearbyAcrossDateLine() {
        let p = Coordinate(latitude: -15, longitude: 179.9)
        let codes = idx.nearby(p, withinKm: 1500).map(\.airport.code)
        #expect(codes.contains("NAN"))
        #expect(codes.contains("APW"))
    }

    @Test func boxQueryAndDateLine() {
        #expect(Set(idx.inBox(minLat: 50, maxLat: 54, minLon: -3, maxLon: 0, minSize: 2, limit: 10).map(\.code)) == ["LHR", "LGW", "MAN"])
        #expect(Set(idx.inBox(minLat: -20, maxLat: -10, minLon: 170, maxLon: -170, minSize: 0, limit: 10).map(\.code)) == ["NAN", "APW"])
        #expect(idx.inBox(minLat: 50, maxLat: 54, minLon: -3, maxLon: 0, minSize: 2, limit: 1).count == 1)
    }

    @Test func searchByCodeNameCityAndAccents() {
        #expect(idx.search("lhr").first?.code == "LHR")
        #expect(idx.search("manch").first?.code == "MAN")
        #expect(Set(idx.search("london").map(\.code)) == ["LHR", "LGW"])
        #expect(idx.search("edimbourg").first?.code == "EDT")
        #expect(idx.search("x").isEmpty)
    }

    @Test func loadsBundledFile() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/airports.json")
        let real = try AirportIndex.load(from: url)
        #expect(real.airports.count > 5000)
        #expect(real.search("JFK").first?.code == "JFK")
        #expect(real.isRealCode("LHR"))
    }
}

@Suite struct NamerTests {
    @Test func stableAndAvoidsRealCodes() {
        let c = Coordinate(latitude: 44.1234, longitude: -101.5678)
        let taken: Set<String> = ["MIL", "MLB", "MIB"]
        let a = PlaceNamer.madeUpPlace(at: c, nearestPlaceName: "Millbrook", locality: "South Dakota", isTaken: { taken.contains($0) })
        let b = PlaceNamer.madeUpPlace(at: c, nearestPlaceName: "Millbrook", locality: "South Dakota", isTaken: { taken.contains($0) })
        #expect(a == b)
        #expect(a.isMadeUp)
        #expect(a.name.hasPrefix("Millbrook "))
        #expect(a.code.count == 3)
        #expect(!taken.contains(a.code))
        #expect(a.code.first == "M")
    }

    @Test func worksWithoutPlaceName() {
        let p = PlaceNamer.madeUpPlace(at: Coordinate(latitude: -20, longitude: 130), nearestPlaceName: nil, locality: nil, isTaken: { _ in false })
        #expect(p.name.split(separator: " ").count == 3)
        #expect(p.code.allSatisfy { ("A"..."Z").contains($0) })
    }

    @Test func allCodesTakenStillReturnsSomething() {
        let p = PlaceNamer.madeUpPlace(at: Coordinate(latitude: 1, longitude: 1), nearestPlaceName: "Ab", locality: nil, isTaken: { $0 != "QQQ" })
        #expect(p.code.count == 3)
    }

    @Test func hashIsStable() {
        #expect(PlaceNamer.stableHash("contrail") == PlaceNamer.stableHash("contrail"))
        #expect(PlaceNamer.stableHash("a") == 0xaf63dc4c8601ec8c)
    }
}

@Suite struct DestinationTests {
    @Test func probesAreOnTheRing() {
        let o = Coordinate(latitude: 40, longitude: -100)
        let pts = DestinationFinder.probePoints(origin: o, minutes: 90, count: 12)
        #expect(pts.count == 12)
        let want = FlightTiming.distanceKm(forMinutes: 90)
        for p in pts { #expect(abs(Geo.distanceKm(o, p.point) - want) < 1) }
    }

    @Test func selectFiltersAndSpreads() {
        let o = Coordinate(latitude: 40, longitude: -100)
        var places: [Place] = []
        for (i, p) in DestinationFinder.probePoints(origin: o, minutes: 60, count: 24).enumerated() {
            places.append(Place(name: "P\(i)", code: "P\(String(format: "%02d", i))", coordinate: p.point, isMadeUp: true))
        }
        places.append(Place(name: "Too close", code: "TCL", coordinate: Geo.destination(from: o, bearing: 0, distanceKm: 20), isMadeUp: true))
        places.append(Place(name: "Too far", code: "TFR", coordinate: Geo.destination(from: o, bearing: 0, distanceKm: 3000), isMadeUp: true))
        let tol = DestinationFinder.tolerance(forMinutes: 60)
        let picks = DestinationFinder.select(origin: o, targetMinutes: 60, candidates: places, tolerance: tol)
        #expect(picks.count == 8)
        #expect(!picks.contains { $0.place.code == "TCL" || $0.place.code == "TFR" })
        for p in picks { #expect(abs(p.minutes - 60) <= tol) }
        let sorted = picks.map(\.bearing).sorted()
        for (a, b) in zip(sorted, sorted.dropFirst()) { #expect(b - a >= 360 / 8 * 0.6 - 1e-9) }
    }

    @Test func toleranceWidens() {
        #expect(DestinationFinder.tolerance(forMinutes: 30) == 5)
        #expect(DestinationFinder.tolerance(forMinutes: 120) == 12)
        #expect(DestinationFinder.tolerance(forMinutes: 120, widen: 2) == 42)
    }
}

@Suite struct LogbookTests {
    let work = FocusCategory(name: "Work", colorHex: "#fff")
    let study = FocusCategory(name: "Study", colorHex: "#000")

    func record(_ start: Date, _ cat: FocusCategory, focusMin: Double, goal: String = "g") -> FlightRecord {
        let p = Place(name: "A, \"B\"", code: "AAA", coordinate: Coordinate(latitude: 0, longitude: 0), isMadeUp: false)
        let q = Place(name: "C", code: "CCC", coordinate: Coordinate(latitude: 1, longitude: 1), isMadeUp: true)
        return FlightRecord(startedAt: start, endedAt: start.addingTimeInterval(focusMin * 60), origin: p, destination: q,
                            distanceKm: 157, plannedSeconds: focusMin * 60, flownSeconds: focusMin * 60, focusSeconds: focusMin * 60,
                            breakCount: 0, categoryID: cat.id, goal: goal, seat: "12A", outcome: .landed)
    }

    @Test func groupsByDayAndCategory() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d1 = Date(timeIntervalSince1970: 86_400 * 10 + 3600)
        let late = Date(timeIntervalSince1970: 86_400 * 10 + 86_000) // 23:53, crosses midnight
        let recs = [record(d1, work, focusMin: 25), record(d1, work, focusMin: 50), record(late, study, focusMin: 30),
                    record(d1.addingTimeInterval(86_400), study, focusMin: 10)]
        let s = Logbook.summary(for: d1, records: recs, calendar: cal)
        #expect(s.totalSessions == 3)
        #expect(s.stats.first { $0.categoryID == work.id }?.sessions == 2)
        #expect(s.stats.first { $0.categoryID == work.id }?.focusMinutes == 75)
        let range = Logbook.daySummaries(records: recs, from: d1, to: d1.addingTimeInterval(86_400 * 2), calendar: cal)
        #expect(range.map(\.totalSessions) == [3, 1, 0])
    }

    @Test func csvEscapes() {
        let csv = Logbook.csv([record(Date(timeIntervalSince1970: 0), work, focusMin: 25, goal: "write, \"edit\"\nship")],
                              categories: [work], timeZone: TimeZone(identifier: "UTC")!)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[0].hasPrefix("start,end,"))
        #expect(csv.contains("\"A, \"\"B\"\"\""))
        #expect(csv.contains("\"write, \"\"edit\"\"\nship\""))
        #expect(csv.contains("1970-01-01 00:00"))
    }

    @Test func totalsCountPlacesAndPartialDistance() {
        var r = record(Date(), work, focusMin: 30)
        r.flownSeconds = r.plannedSeconds / 2
        let t = Logbook.totals([r])
        #expect(t.flights == 1)
        #expect(t.placesVisited == 2)
        #expect(abs(t.distanceKm - 78.5) < 0.01)
        #expect(abs(t.focusHours - 0.5) < 1e-9)
    }

    @Test func formats() {
        #expect(TimeFormat.clock(3849) == "1:04:09")
        #expect(TimeFormat.clock(59.2) == "01:00")
        #expect(TimeFormat.duration(minutes: 125) == "2h 05m")
        #expect(TimeFormat.duration(minutes: 45) == "45 min")
        #expect(DistanceUnit.mi.format(100) == "62 mi")
    }
}
