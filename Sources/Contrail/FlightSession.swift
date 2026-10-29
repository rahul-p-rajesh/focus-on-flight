import ContrailCore
import Foundation
import Observation

/// Everything decided before takeoff.
struct FlightPlan: Equatable {
    var origin: Place
    var destination: Place
    var distanceKm: Double
    /// Whole journey, breaks included. The plane covers the route in exactly this time.
    var duration: TimeInterval
    /// Study (focus) time the user asked for. Breaks are added on top.
    var focusSeconds: TimeInterval
    var schedule: PomodoroSchedule
    var seat: String
    var categoryID: UUID
    var goal: String
    var cruiseAltitude: Double = FlightProfile.cruiseAltitudeM
    var mapLabels = true

    /// - Parameter studyMinutes: focus time; nil uses the route's natural flight time.
    init(origin: Place, destination: Place, schedule: PomodoroSchedule, seat: String, categoryID: UUID, goal: String,
         studyMinutes: Double? = nil, timeScale: Double = 1) {
        self.origin = origin
        self.destination = destination
        self.distanceKm = Geo.distanceKm(origin.coordinate, destination.coordinate)
        var s = schedule
        if timeScale != 1 { s.focusMinutes /= timeScale; s.breakMinutes /= timeScale }
        self.schedule = s
        let study = studyMinutes ?? FlightTiming.minutes(forDistanceKm: distanceKm)
        self.focusSeconds = study * 60 / timeScale
        self.duration = s.duration(forFocus: focusSeconds)
        self.seat = seat
        self.categoryID = categoryID
        self.goal = goal
    }

    var path: [Coordinate] { Geo.path(origin.coordinate, destination.coordinate, segments: 96) }
}

/// A flight in progress. `now` advances on a timer; everything else is derived from it.
@Observable @MainActor final class FlightSession {
    let plan: FlightPlan
    private(set) var clock: FlightClock
    private(set) var now: Date
    /// Advances once per second; the HUD reads this so it is not redrawn on every frame.
    private(set) var slowNow: Date
    let startedAt: Date
    private let cachedSegments: [PomodoroSchedule.Segment]
    var regionName: String?
    /// True during the takeoff sequence, when the scene owns the camera.
    var takeoffRunning = true
    /// Number of on-screen, unobscured views drawing the moving scene. With none, the timer slows to save energy.
    var sceneViewers = 0 { didSet { retime() } }
    var onTick: ((FlightSession) -> Void)?

    private var timer: Timer?
    private var interval: TimeInterval = 0
    var tickInterval: TimeInterval { interval }

    init(plan: FlightPlan, now: Date = Date()) {
        self.plan = plan
        self.clock = FlightClock(duration: plan.duration, startedAt: now)
        self.now = now
        self.slowNow = now
        self.startedAt = now
        self.cachedSegments = plan.schedule.segments(total: plan.duration)
        retime()
    }

    // MARK: Derived state

    var elapsed: TimeInterval { clock.elapsed(at: now) }
    var remaining: TimeInterval { clock.remaining(at: now) }
    var progress: Double { clock.progress(at: now) }
    var isPaused: Bool { clock.isPaused }
    var isFinished: Bool { clock.isFinished(at: now) }
    var landingTime: Date { clock.landingTime(at: slowNow) }
    var hudRemaining: TimeInterval { clock.remaining(at: slowNow) }
    var hudFraction: Double { FlightProfile.routeFraction(elapsed: clock.elapsed(at: slowNow), duration: plan.duration) }
    /// Focus and break periods of this flight, worked out once.
    var segments: [PomodoroSchedule.Segment] { cachedSegments }
    var hudElapsed: TimeInterval { clock.elapsed(at: slowNow) }
    /// "2 of 4" for the current focus block (or the one just finished, during a break).
    var hudFocusPosition: (index: Int, count: Int) {
        let focus = cachedSegments.filter { $0.kind == .focus }
        let e = hudElapsed
        let done = focus.filter { $0.start <= e }.count
        return (max(1, done), focus.count)
    }
    var hudSegmentRemaining: TimeInterval {
        let e = clock.elapsed(at: slowNow)
        return max(0, (plan.schedule.segment(at: e, total: plan.duration)?.end ?? plan.duration) - e)
    }

    var routeFraction: Double { FlightProfile.routeFraction(elapsed: elapsed, duration: plan.duration) }

    var position: Coordinate {
        Geo.interpolate(plan.origin.coordinate, plan.destination.coordinate, fraction: routeFraction)
    }

    /// Direction of travel, used to keep the plane pointing up the screen.
    var heading: Double {
        let f = routeFraction
        let a = Geo.interpolate(plan.origin.coordinate, plan.destination.coordinate, fraction: max(0, min(f, 0.999)))
        let b = Geo.interpolate(plan.origin.coordinate, plan.destination.coordinate, fraction: max(0.001, min(f + 0.001, 1)))
        return Geo.bearing(from: a, to: b)
    }

    var altitude: Double { FlightProfile.altitude(elapsed: elapsed, duration: plan.duration, cruise: plan.cruiseAltitude) }
    var climbProgress: Double { FlightProfile.climbProgress(altitude: altitude, cruise: plan.cruiseAltitude) }

    var segment: PomodoroSchedule.Segment? { plan.schedule.segment(at: elapsed, total: plan.duration) }
    var isOnBreak: Bool { plan.schedule.enabled && segment?.kind == .rest }
    var segmentRemaining: TimeInterval { max(0, (segment?.end ?? plan.duration) - elapsed) }
    var focusElapsed: TimeInterval { plan.schedule.focusElapsed(elapsed, total: plan.duration) }
    var breaksTaken: Int { plan.schedule.segments(total: plan.duration).filter { $0.kind == .rest && $0.end <= elapsed }.count }

    // MARK: Controls

    func pause() { clock.pause(at: Date()); now = Date(); slowNow = now }
    func resume() { clock.resume(at: Date()); now = Date(); slowNow = now }
    func togglePause() { isPaused ? resume() : pause() }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Scene update interval: 10 Hz while climbing or descending (the view zooms), 5 Hz at cruise
    /// (the ground moves only a few points per second), 1 Hz when nothing on screen shows the scene.
    private var desiredInterval: TimeInterval {
        guard sceneViewers > 0 else { return 1 }
        if takeoffRunning || isPaused { return 1.0 / 5 }
        let c = FlightProfile.climbSeconds(duration: plan.duration)
        let e = elapsed
        return (e < c + 5 || e > plan.duration - c - 5) ? 1.0 / 10 : 1.0 / 5
    }

    private func retime() {
        let want = desiredInterval
        guard want != interval || timer == nil else { return }
        interval = want
        timer?.invalidate()
        let t = Timer(timeInterval: want, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let t = Date()
                self.now = t
                if Int(t.timeIntervalSince1970) != Int(self.slowNow.timeIntervalSince1970) {
                    self.slowNow = t
                    self.retime() // phase may have changed
                }
                self.onTick?(self)
            }
        }
        t.tolerance = want * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
