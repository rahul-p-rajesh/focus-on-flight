import Foundation

/// Converts between route distance and flight time.
public enum FlightTiming {
    /// Cruise ground speed. Slower than a real airliner (about 850 km/h) so the ground drifts
    /// calmly across the screen; a 190 km hop takes about half an hour.
    public static let cruiseKmh = 500.0
    /// Fixed allowance for taxi, climb and descent.
    public static let overheadMinutes = 8.0
    public static let minimumDistanceKm = 50.0
    public static let longFlightWarningMinutes = 240.0

    public static func minutes(forDistanceKm d: Double) -> Double {
        overheadMinutes + d / cruiseKmh * 60
    }

    public static func distanceKm(forMinutes m: Double) -> Double {
        max(0, m - overheadMinutes) / 60 * cruiseKmh
    }

    /// Flight time rounded to whole minutes, as the user sees it.
    public static func roundedMinutes(forDistanceKm d: Double) -> Int {
        Int(minutes(forDistanceKm: d).rounded())
    }
}

/// Camera height profile: climb at the start, cruise, descend at the end.
public enum FlightProfile {
    /// Lowest camera height, at takeoff and landing.
    public static let groundAltitudeM = 1_500.0
    /// Default camera height at cruise. The view is about 0.56 times as tall as the camera is high,
    /// so 20 km shows about 11 km of ground. Lower shows more detail and makes the ground move faster on screen.
    public static let cruiseAltitudeM = 20_000.0
    /// How much ground a top-down MapKit view shows, top to bottom, per metre of camera distance (measured).
    public static let viewHeightPerMetre = 0.56

    /// Seconds spent climbing (and descending) for a flight of `duration` seconds.
    public static func climbSeconds(duration: Double) -> Double {
        min(300, max(20, duration * 0.08))
    }

    /// 0 on the ground, 1 at cruise, easing in and out over the climb and the descent.
    public static func climbFraction(elapsed: Double, duration: Double) -> Double {
        guard duration > 0 else { return 1 }
        let c = climbSeconds(duration: duration)
        let up = min(1, max(0, elapsed / c))
        let down = min(1, max(0, (duration - elapsed) / c))
        return smoothstep(min(up, down))
    }

    /// Camera distance in metres at `elapsed` seconds. The height changes geometrically, so the
    /// view widens at an even pace on screen instead of rushing through the first few kilometres.
    public static func altitude(elapsed: Double, duration: Double, cruise: Double = cruiseAltitudeM) -> Double {
        guard duration > 0 else { return cruise }
        let k = climbFraction(elapsed: elapsed, duration: duration)
        if k >= 1 { return cruise }
        if k <= 0 { return groundAltitudeM }
        guard cruise > groundAltitudeM else { return cruise }
        return groundAltitudeM * pow(cruise / groundAltitudeM, k)
    }

    /// 0 on the ground, 1 at cruise: how far through the climb (or descent) the plane is.
    public static func climbProgress(altitude: Double, cruise: Double = cruiseAltitudeM) -> Double {
        guard cruise > groundAltitudeM else { return 1 }
        guard altitude > groundAltitudeM else { return 0 }
        return min(1, log(altitude / groundAltitudeM) / log(cruise / groundAltitudeM))
    }

    static func smoothstep(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    /// Seconds to reach cruise speed after takeoff (and to slow down before landing).
    /// Shorter than the climb, so the plane does not crawl near the airport.
    public static func accelerationSeconds(duration: Double) -> Double {
        min(90, max(10, duration * 0.06))
    }

    /// Fraction of the route covered at `elapsed` seconds. Ground speed eases in and
    /// out at each end so the plane does not jump at takeoff or stop dead on landing.
    public static func routeFraction(elapsed: Double, duration: Double) -> Double {
        guard duration > 0 else { return 1 }
        let t = min(max(elapsed / duration, 0), 1)
        let e = min(0.2, accelerationSeconds(duration: duration) / duration)
        // Piecewise: quadratic ease in [0,e], linear, quadratic ease out [1-e,1].
        let v = 1 / (1 - e) // cruise speed so total area is 1
        if t < e { return v * t * t / (2 * e) }
        if t > 1 - e { let u = 1 - t; return 1 - v * u * u / (2 * e) }
        return v * (t - e / 2)
    }

    /// Ground speed as a fraction of cruise speed: 0 at the runway, 1 at cruise.
    public static func speedFraction(elapsed: Double, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        let t = min(max(elapsed / duration, 0), 1)
        let e = min(0.2, accelerationSeconds(duration: duration) / duration)
        if t < e { return t / e }
        if t > 1 - e { return (1 - t) / e }
        return 1
    }
}
