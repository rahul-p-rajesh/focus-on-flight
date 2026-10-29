import Foundation

/// A point on Earth in degrees.
public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = Geo.normalizedLongitude(longitude)
    }
}

/// Great-circle maths on a spherical Earth.
public enum Geo {
    public static let earthRadiusKm = 6371.0088

    static func rad(_ d: Double) -> Double { d * .pi / 180 }
    static func deg(_ r: Double) -> Double { r * 180 / .pi }

    public static func normalizedLongitude(_ lon: Double) -> Double {
        var l = lon.truncatingRemainder(dividingBy: 360)
        if l > 180 { l -= 360 }
        if l < -180 { l += 360 }
        return l
    }

    /// Central angle between two points, in radians (haversine).
    static func centralAngle(_ a: Coordinate, _ b: Coordinate) -> Double {
        let φ1 = rad(a.latitude), φ2 = rad(b.latitude)
        let dφ = φ2 - φ1, dλ = rad(b.longitude - a.longitude)
        let h = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return 2 * atan2(sqrt(h), sqrt(max(0, 1 - h)))
    }

    public static func distanceKm(_ a: Coordinate, _ b: Coordinate) -> Double {
        centralAngle(a, b) * earthRadiusKm
    }

    /// Initial bearing from a to b, degrees clockwise from north, 0..<360.
    public static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let φ1 = rad(a.latitude), φ2 = rad(b.latitude), dλ = rad(b.longitude - a.longitude)
        let y = sin(dλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(dλ)
        let θ = deg(atan2(y, x))
        return (θ + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Point at `fraction` (0...1) along the great circle from a to b.
    public static func interpolate(_ a: Coordinate, _ b: Coordinate, fraction f: Double) -> Coordinate {
        let δ = centralAngle(a, b)
        if δ < 1e-12 { return a }
        let t = min(max(f, 0), 1)
        let A = sin((1 - t) * δ) / sin(δ), B = sin(t * δ) / sin(δ)
        let φ1 = rad(a.latitude), λ1 = rad(a.longitude), φ2 = rad(b.latitude), λ2 = rad(b.longitude)
        let x = A * cos(φ1) * cos(λ1) + B * cos(φ2) * cos(λ2)
        let y = A * cos(φ1) * sin(λ1) + B * cos(φ2) * sin(λ2)
        let z = A * sin(φ1) + B * sin(φ2)
        return Coordinate(latitude: deg(atan2(z, sqrt(x * x + y * y))), longitude: deg(atan2(y, x)))
    }

    /// Point reached by travelling `distanceKm` from `start` on an initial `bearing`.
    public static func destination(from start: Coordinate, bearing: Double, distanceKm: Double) -> Coordinate {
        let δ = distanceKm / earthRadiusKm, θ = rad(bearing)
        let φ1 = rad(start.latitude), λ1 = rad(start.longitude)
        let φ2 = asin(sin(φ1) * cos(δ) + cos(φ1) * sin(δ) * cos(θ))
        let λ2 = λ1 + atan2(sin(θ) * sin(δ) * cos(φ1), cos(δ) - sin(φ1) * sin(φ2))
        return Coordinate(latitude: deg(φ2), longitude: deg(λ2))
    }

    /// Evenly spaced points along the great circle, for drawing a route.
    public static func path(_ a: Coordinate, _ b: Coordinate, segments: Int = 64) -> [Coordinate] {
        (0...max(1, segments)).map { interpolate(a, b, fraction: Double($0) / Double(max(1, segments))) }
    }

    /// Smallest absolute difference between two bearings, 0...180.
    public static func bearingGap(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }
}
