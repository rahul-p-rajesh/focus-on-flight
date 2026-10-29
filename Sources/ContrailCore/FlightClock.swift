import Foundation

/// Wall-clock based flight timer with pause support. Sleep time counts as
/// flight time, so the plane is at the right place after the Mac wakes.
public struct FlightClock: Codable, Equatable, Sendable {
    public let duration: TimeInterval
    public private(set) var startedAt: Date
    public private(set) var pausedTotal: TimeInterval = 0
    public private(set) var pausedAt: Date?

    public init(duration: TimeInterval, startedAt: Date) {
        self.duration = duration
        self.startedAt = startedAt
    }

    public var isPaused: Bool { pausedAt != nil }

    public func elapsed(at now: Date) -> TimeInterval {
        let end = pausedAt ?? now
        return min(duration, max(0, end.timeIntervalSince(startedAt) - pausedTotal))
    }

    public func remaining(at now: Date) -> TimeInterval { duration - elapsed(at: now) }
    public func progress(at now: Date) -> Double { duration > 0 ? elapsed(at: now) / duration : 1 }
    public func isFinished(at now: Date) -> Bool { elapsed(at: now) >= duration }

    public func landingTime(at now: Date) -> Date { now.addingTimeInterval(remaining(at: now)) }

    public mutating func pause(at now: Date) {
        guard pausedAt == nil else { return }
        pausedAt = now
    }

    public mutating func resume(at now: Date) {
        guard let p = pausedAt else { return }
        pausedTotal += now.timeIntervalSince(p)
        pausedAt = nil
    }
}
