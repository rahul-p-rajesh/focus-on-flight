import Foundation
import Testing
@testable import ContrailCore

let london = Coordinate(latitude: 51.4700, longitude: -0.4543)
let newYork = Coordinate(latitude: 40.6413, longitude: -73.7781)

@Suite struct GeoTests {
    @Test func distanceLondonNewYork() {
        let d = Geo.distanceKm(london, newYork)
        #expect(abs(d - 5555) < 15)
    }

    @Test func bearingIsWestish() {
        let b = Geo.bearing(from: london, to: newYork)
        #expect(b > 280 && b < 300)
    }

    @Test func interpolateEndsAndMiddle() {
        let a = Geo.interpolate(london, newYork, fraction: 0)
        let b = Geo.interpolate(london, newYork, fraction: 1)
        #expect(Geo.distanceKm(a, london) < 0.001)
        #expect(Geo.distanceKm(b, newYork) < 0.001)
        let mid = Geo.interpolate(london, newYork, fraction: 0.5)
        let half = Geo.distanceKm(london, newYork) / 2
        #expect(abs(Geo.distanceKm(london, mid) - half) < 0.5)
        #expect(mid.latitude > 51.5) // great circle bows north
    }

    @Test func destinationRoundTrip() {
        let p = Geo.destination(from: london, bearing: 75, distanceKm: 800)
        #expect(abs(Geo.distanceKm(london, p) - 800) < 0.5)
        #expect(abs(Geo.bearing(from: london, to: p) - 75) < 0.5)
    }

    @Test func crossesDateLine() {
        let a = Coordinate(latitude: 35.55, longitude: 139.78)   // Tokyo
        let b = Coordinate(latitude: 37.62, longitude: -122.38)  // San Francisco
        let mid = Geo.interpolate(a, b, fraction: 0.5)
        #expect(mid.longitude > 160 || mid.longitude < -160)
        #expect(mid.latitude > 45)
    }

    @Test func longitudeNormalised() {
        #expect(Coordinate(latitude: 0, longitude: 190).longitude == -170)
        #expect(Coordinate(latitude: 0, longitude: -540).longitude == 180 || Coordinate(latitude: 0, longitude: -540).longitude == -180)
    }

    @Test func bearingGap() {
        #expect(Geo.bearingGap(350, 10) == 20)
        #expect(Geo.bearingGap(90, 270) == 180)
    }
}

@Suite struct TimingTests {
    @Test func roundTrip() {
        for m in [15.0, 45, 90, 240] {
            #expect(abs(FlightTiming.minutes(forDistanceKm: FlightTiming.distanceKm(forMinutes: m)) - m) < 1e-9)
        }
    }

    @Test func shortHopTakesAboutHalfAnHour() {
        // Rockford to Bloomington, Illinois: 191 km.
        let m = FlightTiming.minutes(forDistanceKm: 191)
        #expect(m > 28 && m < 33)
    }

    @Test func routeFractionIsMonotonicAndBounded() {
        let duration = 3600.0
        var last = -1.0
        for i in 0...1000 {
            let f = FlightProfile.routeFraction(elapsed: Double(i) / 1000 * duration, duration: duration)
            #expect(f >= last - 1e-12)
            last = f
        }
        #expect(abs(FlightProfile.routeFraction(elapsed: 0, duration: duration)) < 1e-12)
        #expect(abs(FlightProfile.routeFraction(elapsed: duration, duration: duration) - 1) < 1e-9)
    }

    @Test func reachesCruiseSpeedQuickly() {
        let d = 3600.0
        // Within two minutes the plane covers ground at close to cruise speed.
        let a = FlightProfile.routeFraction(elapsed: 120, duration: d), b = FlightProfile.routeFraction(elapsed: 130, duration: d)
        let cruise = 10 / (d - FlightProfile.accelerationSeconds(duration: d))
        #expect(abs((b - a) - cruise) / cruise < 0.01)
    }

    @Test func altitudeClimbsCruisesDescends() {
        let d = 3600.0
        #expect(FlightProfile.altitude(elapsed: 0, duration: d) == FlightProfile.groundAltitudeM)
        #expect(FlightProfile.altitude(elapsed: d / 2, duration: d) == FlightProfile.cruiseAltitudeM)
        #expect(FlightProfile.altitude(elapsed: d, duration: d) == FlightProfile.groundAltitudeM)
        #expect(FlightProfile.altitude(elapsed: d / 2, duration: d, cruise: 9_000) == 9_000)
        #expect(FlightProfile.climbProgress(altitude: FlightProfile.groundAltitudeM) == 0)
        #expect(FlightProfile.climbProgress(altitude: 9_000, cruise: 9_000) == 1)
    }

    @Test func climbProgressMatchesAltitude() {
        let d = 3600.0
        for e in stride(from: 0.0, through: d, by: 7) {
            let k = FlightProfile.climbFraction(elapsed: e, duration: d)
            let alt = FlightProfile.altitude(elapsed: e, duration: d)
            #expect(alt >= FlightProfile.groundAltitudeM - 1e-6 && alt <= FlightProfile.cruiseAltitudeM + 1e-6)
            #expect(abs(FlightProfile.climbProgress(altitude: alt) - k) < 1e-9)
        }
    }

    @Test func speedFractionRampsToCruise() {
        let d = 3600.0
        #expect(FlightProfile.speedFraction(elapsed: 0, duration: d) == 0)
        #expect(FlightProfile.speedFraction(elapsed: d / 2, duration: d) == 1)
        #expect(FlightProfile.speedFraction(elapsed: d, duration: d) == 0)
        // Matches the slope of routeFraction.
        let e = 40.0, h = 0.01
        let slope = (FlightProfile.routeFraction(elapsed: e + h, duration: d) - FlightProfile.routeFraction(elapsed: e - h, duration: d)) / (2 * h)
        let cruiseSlope = 1 / (d - FlightProfile.accelerationSeconds(duration: d))
        #expect(abs(slope / cruiseSlope - FlightProfile.speedFraction(elapsed: e, duration: d)) < 1e-4)
    }
}

@Suite struct ClockTests {
    @Test func pauseStopsTime() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var c = FlightClock(duration: 600, startedAt: t0)
        #expect(c.elapsed(at: t0.addingTimeInterval(100)) == 100)
        c.pause(at: t0.addingTimeInterval(100))
        #expect(c.elapsed(at: t0.addingTimeInterval(400)) == 100)
        c.resume(at: t0.addingTimeInterval(400))
        #expect(c.elapsed(at: t0.addingTimeInterval(450)) == 150)
        #expect(c.remaining(at: t0.addingTimeInterval(450)) == 450)
    }

    @Test func sleepCountsAndCaps() {
        let t0 = Date(timeIntervalSince1970: 0)
        let c = FlightClock(duration: 600, startedAt: t0)
        #expect(c.elapsed(at: t0.addingTimeInterval(5_000)) == 600)
        #expect(c.isFinished(at: t0.addingTimeInterval(600)))
    }

    @Test func doublePauseIsHarmless() {
        let t0 = Date(timeIntervalSince1970: 0)
        var c = FlightClock(duration: 600, startedAt: t0)
        c.pause(at: t0.addingTimeInterval(10))
        c.pause(at: t0.addingTimeInterval(20))
        c.resume(at: t0.addingTimeInterval(30))
        c.resume(at: t0.addingTimeInterval(40))
        #expect(c.elapsed(at: t0.addingTimeInterval(50)) == 30)
    }
}
