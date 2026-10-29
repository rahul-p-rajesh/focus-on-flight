import Foundation

/// Where the plane is at any moment of a journey, flown at real cruise speed.
///
/// The plane climbs, cruises and descends along the great circle in `flightSeconds`, the route's natural
/// flight time. If the study session is longer, the extra `holdSeconds` are spent circling in a holding
/// pattern just before the final descent, so it still lands exactly when the session ends. The pattern
/// is a whole number of loops, so the plane leaves it where and how it entered: no jump in position or heading.
public struct FlightTrack: Equatable, Sendable {
    public let origin: Coordinate
    public let destination: Coordinate
    public let flightSeconds: Double
    public let holdSeconds: Double
    public var duration: Double { flightSeconds + holdSeconds }

    /// Shortest hold worth flying a loop for; anything less is absorbed by flying a touch slower.
    public static let minimumHold: Double = 120
    static let preferredRadiusKm = 20.0

    let climb: Double
    let holdStart: Double
    let center: Coordinate
    let radiusKm: Double
    let startBearing: Double
    let degreesPerSecond: Double

    public init(origin: Coordinate, destination: Coordinate, flightSeconds: Double, holdSeconds: Double) {
        self.origin = origin
        self.destination = destination
        var flight = max(1, flightSeconds), hold = max(0, holdSeconds)
        if hold < Self.minimumHold { flight += hold; hold = 0 }
        self.flightSeconds = flight
        self.holdSeconds = hold
        let c = FlightProfile.climbSeconds(duration: flight)
        self.climb = c
        self.holdStart = max(0, flight - c)

        let entryFraction = FlightProfile.routeFraction(elapsed: holdStart, duration: flight)
        let entry = Geo.interpolate(origin, destination, fraction: entryFraction)
        let heading = Self.routeHeading(origin, destination, fraction: entryFraction)
        let distance = FlightTiming.cruiseKmh / 3600 * hold
        let loops = max(1, (distance / (2 * .pi * Self.preferredRadiusKm)).rounded())
        let r = hold > 0 ? distance / (2 * .pi * loops) : Self.preferredRadiusKm
        self.radiusKm = r
        // Right-hand turns, like a standard holding pattern: the centre is off the right wing.
        let ctr = Geo.destination(from: entry, bearing: heading + 90, distanceKm: r)
        self.center = ctr
        self.startBearing = Geo.bearing(from: ctr, to: entry)
        self.degreesPerSecond = hold > 0 ? 360 * loops / hold : 0
    }

    static func routeHeading(_ a: Coordinate, _ b: Coordinate, fraction f: Double) -> Double {
        let p = Geo.interpolate(a, b, fraction: max(0, min(f, 0.999)))
        let q = Geo.interpolate(a, b, fraction: max(0.001, min(f + 0.001, 1)))
        return Geo.bearing(from: p, to: q)
    }

    public func isHolding(at t: Double) -> Bool { holdSeconds > 0 && t >= holdStart && t < holdStart + holdSeconds }

    /// Seconds remaining in the holding pattern (0 when not holding).
    public func holdRemaining(at t: Double) -> Double { isHolding(at: t) ? holdStart + holdSeconds - t : 0 }

    /// Time on the plain route profile: the hold is cut out.
    func routeTime(_ t: Double) -> Double {
        if t < holdStart || holdSeconds == 0 { return min(t, flightSeconds) }
        if t < holdStart + holdSeconds { return holdStart }
        return min(flightSeconds, t - holdSeconds)
    }

    /// Fraction of the route covered (pauses while holding).
    public func routeFraction(at t: Double) -> Double {
        FlightProfile.routeFraction(elapsed: routeTime(max(0, t)), duration: flightSeconds)
    }

    public func position(at t: Double) -> Coordinate {
        if isHolding(at: t) {
            let b = startBearing + degreesPerSecond * (t - holdStart)
            return Geo.destination(from: center, bearing: b, distanceKm: radiusKm)
        }
        return Geo.interpolate(origin, destination, fraction: routeFraction(at: t))
    }

    public func heading(at t: Double) -> Double {
        if isHolding(at: t) {
            return (startBearing + degreesPerSecond * (t - holdStart) + 90).truncatingRemainder(dividingBy: 360)
        }
        return Self.routeHeading(origin, destination, fraction: routeFraction(at: t))
    }

    public func altitude(at t: Double, cruise: Double = FlightProfile.cruiseAltitudeM) -> Double {
        if isHolding(at: t) { return cruise }
        return FlightProfile.altitude(elapsed: routeTime(t), duration: flightSeconds, cruise: cruise)
    }
}
