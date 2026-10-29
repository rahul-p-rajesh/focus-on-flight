import Foundation

/// Splits a flight into focus and break periods.
public struct PomodoroSchedule: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case focus, rest }

    public struct Segment: Equatable, Sendable {
        public let kind: Kind
        public let start: TimeInterval
        public let end: TimeInterval
        public var length: TimeInterval { end - start }
    }

    public var enabled: Bool
    public var focusMinutes: Double
    public var breakMinutes: Double

    public init(enabled: Bool = true, focusMinutes: Double = 25, breakMinutes: Double = 5) {
        self.enabled = enabled
        self.focusMinutes = focusMinutes
        self.breakMinutes = breakMinutes
    }

    /// A break is only added when enough focus time follows it: a fifth of a focus block, at most 5 minutes.
    func minimumTrailingFocus(_ focus: TimeInterval) -> TimeInterval { min(5 * 60, focus * 0.2) }

    public func segments(total: TimeInterval) -> [Segment] {
        guard total > 0 else { return [] }
        let focus = focusMinutes * 60, rest = breakMinutes * 60
        guard enabled, focus > 0, rest > 0 else { return [Segment(kind: .focus, start: 0, end: total)] }
        var out: [Segment] = []
        var t: TimeInterval = 0
        while t < total {
            let end = min(total, t + focus)
            out.append(Segment(kind: .focus, start: t, end: end))
            t = end
            if total - t >= rest + minimumTrailingFocus(focus) {
                out.append(Segment(kind: .rest, start: t, end: t + rest))
                t += rest
            } else if t < total {
                // Too little time for another break and focus block: extend the focus.
                let last = out.removeLast()
                out.append(Segment(kind: .focus, start: last.start, end: total))
                t = total
            }
        }
        return out
    }

    /// Total journey length that gives exactly `focus` seconds of study, with breaks between blocks.
    /// The result fed to `segments(total:)` reproduces that focus time.
    public func duration(forFocus focus: TimeInterval) -> TimeInterval {
        let block = focusMinutes * 60, rest = breakMinutes * 60
        guard enabled, block > 0, rest > 0, focus > block else { return max(0, focus) }
        let full = (focus / block).rounded(.down)
        let leftover = focus - full * block
        let breaks: Double
        if leftover >= minimumTrailingFocus(block) { breaks = full }   // a short last block after a break
        else { breaks = full - 1 }                                      // leftover joins the last block
        return focus + max(0, breaks) * rest
    }

    public func segment(at elapsed: TimeInterval, total: TimeInterval) -> Segment? {
        let segs = segments(total: total)
        return segs.first { elapsed >= $0.start && elapsed < $0.end } ?? segs.last
    }

    public func focusSeconds(total: TimeInterval) -> TimeInterval {
        segments(total: total).filter { $0.kind == .focus }.reduce(0) { $0 + $1.length }
    }

    public func breakSeconds(total: TimeInterval) -> TimeInterval { total - focusSeconds(total: total) }

    /// Focus time already completed after `elapsed` seconds of flight.
    public func focusElapsed(_ elapsed: TimeInterval, total: TimeInterval) -> TimeInterval {
        segments(total: total).filter { $0.kind == .focus }.reduce(0) { acc, s in
            acc + max(0, min(elapsed, s.end) - s.start)
        }
    }

    public func breakCount(total: TimeInterval) -> Int {
        segments(total: total).filter { $0.kind == .rest }.count
    }
}
