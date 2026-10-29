import Foundation
import Testing
@testable import ContrailCore

@Suite struct TrackTests {
    let a = Coordinate(latitude: 41.97, longitude: -87.90) // Chicago
    let b = Coordinate(latitude: 40.66, longitude: -89.69) // Peoria

    func natural(_ x: Coordinate, _ y: Coordinate) -> Double { FlightTiming.minutes(forDistanceKm: Geo.distanceKm(x, y)) * 60 }

    @Test func noHoldMatchesPlainProfile() {
        let f = natural(a, b)
        let t = FlightTrack(origin: a, destination: b, flightSeconds: f, holdSeconds: 0)
        #expect(t.duration == f)
        #expect(Geo.distanceKm(t.position(at: 0), a) < 0.01)
        #expect(Geo.distanceKm(t.position(at: f), b) < 0.01)
        #expect(!t.isHolding(at: f / 2))
    }

    @Test func holdIsSeamlessAndLandsOnTime() {
        let f = natural(a, b), hold = 95.0 * 60
        let t = FlightTrack(origin: a, destination: b, flightSeconds: f, holdSeconds: hold)
        #expect(t.duration == f + hold)
        let enter = t.holdStart, exit = t.holdStart + hold
        // Position and heading are continuous on entry and exit.
        for edge in [enter, exit] {
            let before = t.position(at: edge - 0.5), after = t.position(at: edge + 0.5)
            #expect(Geo.distanceKm(before, after) < 0.5)
            #expect(Geo.bearingGap(t.heading(at: edge - 0.5), t.heading(at: edge + 0.5)) < 3)
        }
        // While holding, the plane stays near the destination and at cruise.
        for s in stride(from: enter, to: exit, by: 60) {
            #expect(t.isHolding(at: s))
            #expect(Geo.distanceKm(t.position(at: s), b) < 80)
            #expect(t.altitude(at: s) == FlightProfile.cruiseAltitudeM)
        }
        #expect(Geo.distanceKm(t.position(at: t.duration), b) < 0.01)
        #expect(t.altitude(at: t.duration) == FlightProfile.groundAltitudeM)
        #expect(t.radiusKm > 10 && t.radiusKm < 35)
    }

    @Test func groundSpeedStaysRealWhileHolding() {
        let f = natural(a, b)
        let t = FlightTrack(origin: a, destination: b, flightSeconds: f, holdSeconds: 3600)
        let s = t.holdStart + 600
        let kmh = Geo.distanceKm(t.position(at: s), t.position(at: s + 10)) / 10 * 3600
        #expect(abs(kmh - FlightTiming.cruiseKmh) < 25)
    }

    @Test func tinyHoldIsAbsorbed() {
        let t = FlightTrack(origin: a, destination: b, flightSeconds: 1000, holdSeconds: 60)
        #expect(t.holdSeconds == 0)
        #expect(t.duration == 1060)
    }
}
