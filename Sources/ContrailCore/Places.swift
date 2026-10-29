import Foundation

/// A departure or arrival point. Either a real airport or a made-up airfield.
public struct Place: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var code: String
    public var locality: String?
    public var coordinate: Coordinate
    public var isMadeUp: Bool

    public var id: String { "\(code)-\(coordinate.latitude)-\(coordinate.longitude)" }

    public init(name: String, code: String, locality: String? = nil, coordinate: Coordinate, isMadeUp: Bool) {
        self.name = name
        self.code = code
        self.locality = locality
        self.coordinate = coordinate
        self.isMadeUp = isMadeUp
    }
}

public struct Airport: Hashable, Sendable {
    public let name: String
    public let code: String
    public let city: String
    public let coordinate: Coordinate
    /// 2 = large, 1 = medium, 0 = small.
    public let size: Int

    public init(name: String, code: String, city: String, coordinate: Coordinate, size: Int) {
        self.name = name
        self.code = code
        self.city = city
        self.coordinate = coordinate
        self.size = size
    }

    public var place: Place {
        Place(name: name, code: code, locality: city.isEmpty ? nil : city, coordinate: coordinate, isMadeUp: false)
    }
}

/// Fast lookups over the bundled airport list.
public final class AirportIndex: Sendable {
    public let airports: [Airport]
    private let codes: Set<String>
    private let grid: [Int: [Int]]
    private let searchKeys: [(name: String, city: String)]

    /// Distance within which a chosen point snaps to a real airport.
    public static let snapRadiusKm = 30.0

    public init(airports: [Airport]) {
        self.airports = airports
        self.codes = Set(airports.map(\.code))
        var g: [Int: [Int]] = [:]
        for (i, a) in airports.enumerated() {
            g[Self.cell(a.coordinate.latitude, a.coordinate.longitude), default: []].append(i)
        }
        self.grid = g
        self.searchKeys = airports.map { (Self.fold($0.name), Self.fold($0.city)) }
    }

    /// Loads the JSON produced by tools/airports/build_airports.py.
    public static func load(from url: URL) throws -> AirportIndex {
        struct File: Decodable { let airports: [[Value]] }
        enum Value: Decodable {
            case s(String), d(Double)
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let d = try? c.decode(Double.self) { self = .d(d) } else { self = .s(try c.decode(String.self)) }
            }
            var string: String { if case .s(let s) = self { return s }; return "" }
            var double: Double { if case .d(let d) = self { return d }; return 0 }
        }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        let list = file.airports.compactMap { row -> Airport? in
            guard row.count >= 6 else { return nil }
            return Airport(name: row[0].string, code: row[1].string, city: row[2].string,
                           coordinate: Coordinate(latitude: row[3].double, longitude: row[4].double),
                           size: Int(row[5].double))
        }
        return AirportIndex(airports: list)
    }

    static func cell(_ lat: Double, _ lon: Double) -> Int {
        let la = Int(floor(lat)) + 90, lo = Int(floor(Geo.normalizedLongitude(lon))) + 180
        return la * 1000 + lo
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    public func isRealCode(_ code: String) -> Bool { codes.contains(code.uppercased()) }

    /// Airports within `radiusKm`, closest first.
    public func nearby(_ c: Coordinate, withinKm radiusKm: Double, limit: Int = 10) -> [(airport: Airport, km: Double)] {
        let latCells = Int(ceil(radiusKm / 111)) + 1
        let cosLat = max(0.05, cos(c.latitude * .pi / 180))
        let lonCells = min(180, Int(ceil(radiusKm / (111 * cosLat))) + 1)
        let la0 = Int(floor(c.latitude)), lo0 = Int(floor(c.longitude))
        var found: [(Airport, Double)] = []
        for dla in -latCells...latCells {
            let la = la0 + dla
            guard la >= -90, la < 90 else { continue }
            for dlo in -lonCells...lonCells {
                let key = (la + 90) * 1000 + (Int(Geo.normalizedLongitude(Double(lo0 + dlo))) + 180)
                for i in grid[key] ?? [] {
                    let d = Geo.distanceKm(c, airports[i].coordinate)
                    if d <= radiusKm { found.append((airports[i], d)) }
                }
            }
        }
        // Dedupe in case longitude wrapping visited a cell twice.
        var seen = Set<String>()
        return found.sorted { $0.1 < $1.1 }.filter { seen.insert($0.0.code).inserted }.prefix(limit).map { ($0.0, $0.1) }
    }

    public func nearest(_ c: Coordinate, withinKm radiusKm: Double) -> (airport: Airport, km: Double)? {
        nearby(c, withinKm: radiusKm, limit: 1).first
    }

    /// Airports inside a latitude/longitude box, biggest first. Handles boxes that cross the date line.
    public func inBox(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, minSize: Int, limit: Int) -> [Airport] {
        let wraps = minLon > maxLon
        return airports.lazy.filter { a in
            let c = a.coordinate
            guard a.size >= minSize, c.latitude >= minLat, c.latitude <= maxLat else { return false }
            return wraps ? (c.longitude >= minLon || c.longitude <= maxLon) : (c.longitude >= minLon && c.longitude <= maxLon)
        }.prefix(limit).map { $0 }
    }

    /// Text search over code, airport name and city.
    public func search(_ query: String, limit: Int = 8) -> [Airport] {
        let q = Self.fold(query.trimmingCharacters(in: .whitespaces))
        guard q.count >= 2 else { return [] }
        let upper = q.uppercased()
        var scored: [(Int, Int)] = []
        for (i, a) in airports.enumerated() {
            var score = 0
            if a.code == upper { score = 1000 }
            else if q.count <= 3, a.code.hasPrefix(upper) { score = 300 }
            else {
                let k = searchKeys[i]
                if k.city.hasPrefix(q) { score = 200 }
                else if k.name.hasPrefix(q) || k.name.contains(" " + q) { score = 150 }
                else if k.city.contains(q) || k.name.contains(q) { score = 60 }
            }
            if score > 0 { scored.append((score + a.size * 40, i)) }
        }
        return scored.sorted { $0.0 > $1.0 || ($0.0 == $1.0 && $0.1 < $1.1) }.prefix(limit).map { airports[$0.1] }
    }
}

/// Makes stable, made-up airfield names for points with no airport nearby.
public enum PlaceNamer {
    /// FNV-1a: stable across launches, unlike Swift's Hasher.
    public static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x0000_0100_0000_01B3 }
        return h
    }

    static let suffixesNamed = ["Field", "Airfield", "Airstrip", "Landing", "Strip", "Aerodrome"]
    static let first = ["Kestrel", "Cedar", "Heron", "Juniper", "Falcon", "Willow", "Granite", "Sparrow", "Aspen",
                        "Harbor", "Lark", "Maple", "Osprey", "Silver", "Amber", "Copper", "Fern", "Basalt", "Wren", "Tamarack"]
    static let second = ["Valley", "Ridge", "Plains", "Hollow", "Creek", "Mesa", "Point", "Bay", "Meadow", "Bluff",
                         "Cove", "Heights", "Flats", "Springs", "Basin", "Crossing"]
    static let suffixesFree = ["Airfield", "Field", "Airstrip"]

    static func key(_ c: Coordinate) -> String {
        String(format: "%.2f,%.2f", c.latitude, c.longitude)
    }

    /// - Parameters:
    ///   - nearestPlaceName: a nearby town or city, if one is known.
    ///   - isTaken: returns true for codes that belong to real airports.
    public static func madeUpPlace(at c: Coordinate, nearestPlaceName: String?, locality: String?,
                                   isTaken: (String) -> Bool) -> Place {
        let h = stableHash(key(c))
        let name: String
        if let base = nearestPlaceName?.trimmingCharacters(in: .whitespaces), !base.isEmpty {
            name = "\(base) \(suffixesNamed[Int(h % UInt64(suffixesNamed.count))])"
        } else {
            let a = first[Int(h % UInt64(first.count))]
            let b = second[Int((h / 31) % UInt64(second.count))]
            let s = suffixesFree[Int((h / 977) % UInt64(suffixesFree.count))]
            name = "\(a) \(b) \(s)"
        }
        return Place(name: name, code: code(for: name, seed: h, isTaken: isTaken),
                     locality: locality ?? nearestPlaceName, coordinate: c, isMadeUp: true)
    }

    public static func code(for name: String, seed: UInt64, isTaken: (String) -> Bool) -> String {
        let letters = Array(name.uppercased().folding(options: .diacriticInsensitive, locale: nil).filter { ("A"..."Z").contains($0) })
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var h = seed
        func next() -> UInt64 { h = h &* 6364136223846793005 &+ 1442695040888963407; return h >> 33 }
        if letters.count >= 3 {
            for _ in 0..<60 {
                let i = Int(next() % UInt64(letters.count - 1)) + 1
                var j = Int(next() % UInt64(letters.count - 1)) + 1
                if j == i { j = (j % (letters.count - 1)) + 1 }
                let (x, y) = (min(i, j), max(i, j))
                let c = String([letters[0], letters[x], letters[y]])
                if !isTaken(c) { return c }
            }
        }
        for _ in 0..<500 {
            let c = String((0..<3).map { _ in alphabet[Int(next() % 26)] })
            if !isTaken(c) { return c }
        }
        return "ZZZ"
    }
}

/// A suggested destination for "plan by duration".
public struct DestinationCandidate: Hashable, Sendable, Identifiable {
    public let place: Place
    public let distanceKm: Double
    public let minutes: Double
    public let bearing: Double
    public var id: String { place.id }
}

public enum DestinationFinder {
    /// Points around the reachable ring, one per direction.
    public static func probePoints(origin: Coordinate, minutes: Double, count: Int = 24, rotation: Double = 0)
        -> [(bearing: Double, point: Coordinate)] {
        let d = FlightTiming.distanceKm(forMinutes: minutes)
        return (0..<count).map { i in
            let b = (Double(i) * 360 / Double(count) + rotation).truncatingRemainder(dividingBy: 360)
            return (b, Geo.destination(from: origin, bearing: b, distanceKm: d))
        }
    }

    /// Allowed difference in minutes. `widen` 0, 1, 2 gives ±10 %, ±20 %, ±35 %, never under 5 minutes.
    public static func tolerance(forMinutes m: Double, widen: Int = 0) -> Double {
        let pct = [0.10, 0.20, 0.35][min(max(widen, 0), 2)]
        return max(5 * Double(widen + 1), m * pct)
    }

    /// Picks up to `limit` destinations near the target time, spread across directions.
    public static func select(origin: Coordinate, targetMinutes: Double, candidates: [Place],
                              tolerance: Double, limit: Int = 8) -> [DestinationCandidate] {
        var seen = Set<String>()
        let pool: [DestinationCandidate] = candidates.compactMap { p in
            guard seen.insert(p.code).inserted else { return nil }
            let d = Geo.distanceKm(origin, p.coordinate)
            guard d >= FlightTiming.minimumDistanceKm else { return nil }
            let m = FlightTiming.minutes(forDistanceKm: d)
            guard abs(m - targetMinutes) <= tolerance else { return nil }
            return DestinationCandidate(place: p, distanceKm: d, minutes: m, bearing: Geo.bearing(from: origin, to: p.coordinate))
        }.sorted { abs($0.minutes - targetMinutes) < abs($1.minutes - targetMinutes) }

        let minGap = 360.0 / Double(max(limit, 1)) * 0.6
        var chosen: [DestinationCandidate] = []
        for c in pool where chosen.count < limit {
            if chosen.allSatisfy({ Geo.bearingGap($0.bearing, c.bearing) >= minGap }) { chosen.append(c) }
        }
        for c in pool where chosen.count < limit && !chosen.contains(c) { chosen.append(c) }
        return chosen.sorted { $0.bearing < $1.bearing }
    }
}

public enum Seat {
    /// A random window seat such as "14A" or "27F".
    public static func randomWindow<G: RandomNumberGenerator>(using g: inout G) -> String {
        "\(Int.random(in: 6...34, using: &g))\(Bool.random(using: &g) ? "A" : "F")"
    }
}
