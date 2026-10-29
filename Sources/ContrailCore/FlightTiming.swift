import Foundation

/// Converts between route distance and flight time.
public enum FlightTiming {
    public static let cruiseKmh = 850.0
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
    /// Lowest camera height. Lower than this, imagery in remote areas turns soft.
    public static let groundAltitudeM = 3_200.0
    /// Default camera height at cruise. Lower shows more detail.
    public static let cruiseAltitudeM = 10_000.0

    /// Seconds spent climbing (and descending) for a flight of `duration` seconds.
    public static func climbSeconds(duration: Double) -> Double {
        min(300, max(20, duration * 0.08))
    }

    /// Camera distance in metres at `elapsed` seconds.
    public static func altitude(elapsed: Double, duration: Double, cruise: Double = cruiseAltitudeM) -> Double {
        guard duration > 0 else { return cruise }
        let c = climbSeconds(duration: duration)
        let up = min(1, max(0, elapsed / c))
        let down = min(1, max(0, (duration - elapsed) / c))
        let k = smoothstep(min(up, down))
        return groundAltitudeM + (cruise - groundAltitudeM) * k
    }

    /// 0 on the ground, 1 at cruise: how far through the climb (or descent) the plane is.
    public static func climbProgress(altitude: Double, cruise: Double = cruiseAltitudeM) -> Double {
        guard cruise > groundAltitudeM else { return 1 }
        return min(1, max(0, (altitude - groundAltitudeM) / (cruise - groundAltitudeM)))
    }

    static func smoothstep(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    /// Fraction of the route covered at `elapsed` seconds. Ground speed eases in and
    /// out during climb and descent so the plane does not jump at takeoff.
    public static func routeFraction(elapsed: Double, duration: Double) -> Double {
        guard duration > 0 else { return 1 }
        let t = min(max(elapsed / duration, 0), 1)
        let e = min(0.2, climbSeconds(duration: duration) / duration)
        // Piecewise: quadratic ease in [0,e], linear, quadratic ease out [1-e,1].
        let v = 1 / (1 - e) // cruise speed so total area is 1
        if t < e { return v * t * t / (2 * e) }
        if t > 1 - e { let u = 1 - t; return 1 - v * u * u / (2 * e) }
        return v * (t - e / 2)
    }
}
