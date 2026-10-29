import Foundation

public struct FocusCategory: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var archived: Bool

    public init(id: UUID = UUID(), name: String, colorHex: String, archived: Bool = false) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.archived = archived
    }

    public static let defaults: [FocusCategory] = [
        FocusCategory(name: "Work", colorHex: "#6FA8DC"),
        FocusCategory(name: "Study", colorHex: "#93C47D"),
        FocusCategory(name: "Reading", colorHex: "#E6B85C"),
        FocusCategory(name: "Writing", colorHex: "#C27BA0"),
        FocusCategory(name: "Coding", colorHex: "#76A5AF"),
    ]
}

public enum FlightOutcome: String, Codable, Sendable { case landed, endedEarly }

public struct FlightRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var origin: Place
    public var destination: Place
    public var distanceKm: Double
    public var plannedSeconds: TimeInterval
    public var flownSeconds: TimeInterval
    public var focusSeconds: TimeInterval
    public var breakCount: Int
    public var categoryID: UUID
    public var goal: String
    public var goalDone: Bool
    public var seat: String
    public var outcome: FlightOutcome

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date, origin: Place, destination: Place,
                distanceKm: Double, plannedSeconds: TimeInterval, flownSeconds: TimeInterval,
                focusSeconds: TimeInterval, breakCount: Int, categoryID: UUID, goal: String,
                goalDone: Bool = false, seat: String, outcome: FlightOutcome) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.origin = origin
        self.destination = destination
        self.distanceKm = distanceKm
        self.plannedSeconds = plannedSeconds
        self.flownSeconds = flownSeconds
        self.focusSeconds = focusSeconds
        self.breakCount = breakCount
        self.categoryID = categoryID
        self.goal = goal
        self.goalDone = goalDone
        self.seat = seat
        self.outcome = outcome
    }
}

public struct CategoryDayStat: Hashable, Sendable {
    public let categoryID: UUID
    public let sessions: Int
    public let focusMinutes: Double
}

public struct DaySummary: Hashable, Sendable {
    public let day: Date
    public let stats: [CategoryDayStat]
    public var totalSessions: Int { stats.reduce(0) { $0 + $1.sessions } }
    public var totalMinutes: Double { stats.reduce(0) { $0 + $1.focusMinutes } }
}

public struct LogbookTotals: Equatable, Sendable {
    public let focusHours: Double
    public let flights: Int
    public let distanceKm: Double
    public let placesVisited: Int
}

public enum Logbook {
    /// Summary for the day that contains `day`. A flight counts on its start day.
    public static func summary(for day: Date, records: [FlightRecord], calendar: Calendar = .current) -> DaySummary {
        let start = calendar.startOfDay(for: day)
        var byCat: [UUID: (Int, Double)] = [:]
        for r in records where calendar.isDate(r.startedAt, inSameDayAs: start) {
            let cur = byCat[r.categoryID] ?? (0, 0)
            byCat[r.categoryID] = (cur.0 + 1, cur.1 + r.focusSeconds / 60)
        }
        let stats = byCat.map { CategoryDayStat(categoryID: $0.key, sessions: $0.value.0, focusMinutes: $0.value.1) }
            .sorted { $0.focusMinutes > $1.focusMinutes }
        return DaySummary(day: start, stats: stats)
    }

    /// One summary per day from `from` to `to`, including empty days.
    public static func daySummaries(records: [FlightRecord], from: Date, to: Date, calendar: Calendar = .current) -> [DaySummary] {
        var out: [DaySummary] = []
        var d = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        while d <= end {
            out.append(summary(for: d, records: records, calendar: calendar))
            guard let n = calendar.date(byAdding: .day, value: 1, to: d) else { break }
            d = n
        }
        return out
    }

    public static func totals(_ records: [FlightRecord]) -> LogbookTotals {
        var places = Set<String>()
        for r in records { places.insert(r.origin.code); places.insert(r.destination.code) }
        return LogbookTotals(
            focusHours: records.reduce(0) { $0 + $1.focusSeconds } / 3600,
            flights: records.count,
            distanceKm: records.reduce(0) { $0 + $1.distanceKm * min(1, $1.flownSeconds / max($1.plannedSeconds, 1)) },
            placesVisited: places.count)
    }

    public static func csv(_ records: [FlightRecord], categories: [FocusCategory], timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let names = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        func esc(_ s: String) -> String {
            s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
                ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        var lines = ["start,end,from_code,from_name,to_code,to_name,distance_km,planned_min,focus_min,breaks,category,goal,goal_done,seat,outcome"]
        for r in records.sorted(by: { $0.startedAt < $1.startedAt }) {
            lines.append([
                f.string(from: r.startedAt), f.string(from: r.endedAt),
                r.origin.code, esc(r.origin.name), r.destination.code, esc(r.destination.name),
                String(format: "%.0f", r.distanceKm), String(format: "%.0f", r.plannedSeconds / 60),
                String(format: "%.0f", r.focusSeconds / 60), String(r.breakCount),
                esc(names[r.categoryID] ?? "Unknown"), esc(r.goal), r.goalDone ? "yes" : "no", r.seat, r.outcome.rawValue,
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

public enum DistanceUnit: String, Codable, CaseIterable, Sendable {
    case km, mi
    public func format(_ km: Double) -> String {
        let v = self == .km ? km : km * 0.621371
        let n = NumberFormatter()
        n.numberStyle = .decimal
        n.maximumFractionDigits = 0
        return "\(n.string(from: NSNumber(value: v.rounded())) ?? "0") \(rawValue)"
    }
}

public enum TimeFormat {
    /// "1:04:09" or "04:09".
    public static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    /// "2h 05m" or "45 min".
    public static func duration(minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? String(format: "%dh %02dm", m / 60, m % 60) : "\(m) min"
    }
}
