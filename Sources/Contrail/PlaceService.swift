import ContrailCore
import CoreLocation
import Foundation
import MapKit

struct PlaceResult: Identifiable, Hashable {
    enum Kind: Hashable { case airport, place }
    let id: String
    let title: String
    let subtitle: String
    let coordinate: Coordinate
    let kind: Kind
    let airport: Airport?
    /// Town or city name to base a made-up airfield name on.
    let nameHint: String?
}

extension Coordinate {
    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    init(_ c: CLLocationCoordinate2D) { self.init(latitude: c.latitude, longitude: c.longitude) }
}

/// Place search, naming and destination suggestions, backed by the airport list and Apple Maps.
@MainActor final class PlaceService {
    let airports: AirportIndex

    init(airports: AirportIndex) { self.airports = airports }

    // MARK: Search

    func searchAirports(_ q: String) -> [PlaceResult] {
        airports.search(q, limit: 5).map { a in
            PlaceResult(id: "apt-\(a.code)", title: "\(a.code) · \(a.name)", subtitle: a.city, coordinate: a.coordinate,
                        kind: .airport, airport: a, nameHint: a.city)
        }
    }

    func searchPlaces(_ q: String) async -> [PlaceResult] {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = trimmed
        req.resultTypes = [.address, .pointOfInterest]
        guard let resp = try? await MKLocalSearch(request: req).start() else { return [] }
        return resp.mapItems.prefix(6).map { item in
            let c = Coordinate(item.location.coordinate)
            let reps = item.addressRepresentations
            let city = reps?.cityName
            let title = item.name ?? city ?? "Place"
            let subtitle = reps?.cityWithContext ?? item.address?.shortAddress ?? ""
            return PlaceResult(id: "mk-\(c.latitude),\(c.longitude)-\(title)", title: title, subtitle: subtitle,
                               coordinate: c, kind: .place, airport: nil, nameHint: city ?? item.name)
        }
    }

    // MARK: Naming

    /// Turns a chosen point into a Place: a real airport within 30 km, otherwise a made-up airfield.
    func resolve(_ c: Coordinate, nameHint: String? = nil) async -> Place {
        if let hit = airports.nearest(c, withinKm: AirportIndex.snapRadiusKm) { return hit.airport.place }
        var hint = nameHint
        var locality: String?
        if let info = await reverse(c) {
            hint = hint ?? info.city
            locality = [info.city, info.region].compactMap { $0 }.joined(separator: ", ")
            if locality?.isEmpty == true { locality = nil }
        }
        return PlaceNamer.madeUpPlace(at: c, nearestPlaceName: hint, locality: locality, isTaken: { [airports] in airports.isRealCode($0) })
    }

    func resolve(_ r: PlaceResult) async -> Place {
        if let a = r.airport { return a.place }
        return await resolve(r.coordinate, nameHint: r.nameHint)
    }

    struct ReverseInfo { let city: String?; let region: String?; let name: String? }

    func reverse(_ c: Coordinate) async -> ReverseInfo? {
        guard let req = MKReverseGeocodingRequest(location: CLLocation(latitude: c.latitude, longitude: c.longitude)) else { return nil }
        guard let item = try? await req.mapItems.first else { return nil }
        let reps = item.addressRepresentations
        return ReverseInfo(city: reps?.cityName, region: reps?.regionName, name: item.name)
    }

    /// "Nebraska", "Lake Michigan", "Atlantic Ocean"...
    func regionName(at c: Coordinate) async -> String? {
        guard let info = await reverse(c) else { return nil }
        return info.region ?? info.city ?? info.name
    }

    // MARK: Suggestions

    /// Destinations about `minutes` away, spread around the compass.
    func suggestions(origin: Coordinate, minutes: Double, rotation: Double) async -> (picks: [DestinationCandidate], widened: Bool) {
        let ringKm = FlightTiming.distanceKm(forMinutes: minutes)
        let probes = DestinationFinder.probePoints(origin: origin, minutes: minutes, count: 24, rotation: rotation)
        let radius = min(150, max(40, ringKm * 0.15))
        var candidates: [Place] = []
        var coveredBearings: [Double] = []
        for p in probes {
            let near = airports.nearby(p.point, withinKm: radius, limit: 3)
            candidates += near.map { $0.airport.place }
            if !near.isEmpty { coveredBearings.append(p.bearing) }
        }
        // Fill directions with no airport using made-up airfields at real towns (skip open water).
        var lookups = 0
        for p in probes where lookups < 10 && !coveredBearings.contains(where: { Geo.bearingGap($0, p.bearing) < 20 }) {
            lookups += 1
            guard let info = await reverse(p.point), info.city != nil || info.region != nil else { continue }
            candidates.append(PlaceNamer.madeUpPlace(at: p.point, nearestPlaceName: info.city, locality: info.region,
                                                     isTaken: { [airports] in airports.isRealCode($0) }))
            coveredBearings.append(p.bearing)
        }
        for widen in 0...2 {
            let picks = DestinationFinder.select(origin: origin, targetMinutes: minutes, candidates: candidates,
                                                 tolerance: DestinationFinder.tolerance(forMinutes: minutes, widen: widen), limit: 6)
            if picks.count >= 3 || widen == 2 { return (picks, widen > 0) }
        }
        return ([], false)
    }
}

/// One-shot current location.
@MainActor final class LocationFetcher: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func current() async -> CLLocation? {
        if continuation != nil { return nil }
        return await withCheckedContinuation { cont in
            continuation = cont
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .denied, .restricted: finish(nil)
            default: manager.requestLocation()
            }
        }
    }

    private func finish(_ l: CLLocation?) {
        continuation?.resume(returning: l)
        continuation = nil
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        guard continuation != nil else { return }
        switch m.authorizationStatus {
        case .notDetermined: break
        case .denied, .restricted: finish(nil)
        default: m.requestLocation()
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) { finish(locations.last) }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) { finish(nil) }
}
