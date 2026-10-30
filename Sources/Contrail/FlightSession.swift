import ContrailCore
import Foundation
import Observation

/// Everything decided before takeoff. The session lasts exactly the route's real flight time.
struct FlightPlan: Equatable {
    var origin: Place
    var destination: Place
    var distanceKm: Double
    /// Flight time: taxi, climb, cruise at `FlightTiming.cruiseKmh`, descent.
    var duration: TimeInterval
    /// The path flown at real cruise speed.
    var track: FlightTrack
    var seat: String
    /// Test-only speed-up; 1 in normal use.
    var timeScale: Double
    var categoryID: UUID
    var goal: String
    /// Camera height at cruise, in metres.
    var cruiseAltitude: Double = FlightProfile.cruiseAltitudeM
    /// Cruising altitude shown to the user, in feet.
    var cruiseFeet: Double = 36_000
    var mapLabels = true

    init(origin: Place, destination: Place, seat: String, categoryID: UUID, goal: String, timeScale: Double = 1) {
        self.origin = origin
        self.destination = destination
        self.distanceKm = Geo.distanceKm(origin.coordinate, destination.coordinate)
        let seconds = FlightTiming.minutes(forDistanceKm: distanceKm) * 60 / timeScale
        self.track = FlightTrack(origin: origin.coordinate, destination: destination.coordinate, flightSeconds: seconds, holdSeconds: 0)
        self.duration = track.duration
        self.timeScale = timeScale
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
    var regionName: String?
    /// True during the takeoff sequence, when the scene owns the camera.
    var takeoffRunning = true
    /// Set when the flight is ended early and the plane is going down. The clock is frozen from then on.
    private(set) var crashStart: Date?
    var isCrashing: Bool { crashStart != nil }
    /// Number of on-screen, unobscured views drawing the moving scene. With none, the timer slows to save energy.
    var sceneViewers = 0 { didSet { retime() } }
    var onTick: ((FlightSession) -> Void)?

    private var timer: Timer?
    private var interval: TimeInterval = 0
    /// Set once the flight has ended. A stopped session never ticks again, even if a view
    /// that still holds it changes its visibility count.
    private(set) var isStopped = false
    var tickInterval: TimeInterval { interval }

    init(plan: FlightPlan, now: Date = Date()) {
        self.plan = plan
        self.clock = FlightClock(duration: plan.duration, startedAt: now)
        self.now = now
        self.slowNow = now
        self.startedAt = now
        retime()
    }

    // MARK: Derived state

    var elapsed: TimeInterval { clock.elapsed(at: now) }
    var remaining: TimeInterval { clock.remaining(at: now) }
    var progress: Double { clock.progress(at: now) }
    var isPaused: Bool { clock.isPaused }
    var isFinished: Bool { clock.isFinished(at: now) }

    var routeFraction: Double { plan.track.routeFraction(at: elapsed) }
    var position: Coordinate { plan.track.position(at: elapsed) }
    /// Direction of travel, used to keep the plane pointing up the screen.
    var heading: Double { plan.track.heading(at: elapsed) }
    var altitude: Double { plan.track.altitude(at: elapsed, cruise: plan.cruiseAltitude) }
    var climbProgress: Double { FlightProfile.climbProgress(altitude: altitude, cruise: plan.cruiseAltitude) }
    /// Metres per second the ground moves under the plane, in wall-clock time.
    var groundSpeedMps: Double { isPaused ? 0 : trackSpeedMps(at: elapsed) }

    /// Ground speed along the route at `t`, in metres per wall-clock second.
    private func trackSpeedMps(at t: TimeInterval) -> Double {
        let h = 0.5, a = max(0, t - h), b = t + h
        let d = plan.track.routeFraction(at: b) - plan.track.routeFraction(at: a)
        return max(0, d) * plan.distanceKm * 1000 / (b - a)
    }

    // Once-a-second values for the HUD and menu bar.
    var hudElapsed: TimeInterval { clock.elapsed(at: slowNow) }
    var hudRemaining: TimeInterval { clock.remaining(at: slowNow) }
    var hudFraction: Double { plan.track.routeFraction(at: hudElapsed) }
    /// Plane position and heading, updated once a second, for zoomed-out views where faster updates only add jitter.
    var hudPosition: Coordinate { plan.track.position(at: hudElapsed) }
    var hudHeading: Double { plan.track.heading(at: hudElapsed) }
    var landingTime: Date { clock.landingTime(at: slowNow) }
    /// Altitude and ground speed for the flight card, updated once a second.
    var hudAltitudeFeet: Double { plan.cruiseFeet * plan.track.climbFraction(at: hudElapsed) }
    /// The plane's true ground speed, so the number matches how fast the map moves.
    var hudSpeedKmh: Double { trackSpeedMps(at: hudElapsed) * 3.6 / plan.timeScale }

    // MARK: Controls

    func pause() { clock.pause(at: Date()); now = Date(); slowNow = now }
    func resume() { clock.resume(at: Date()); now = Date(); slowNow = now }
    func togglePause() { guard !isCrashing else { return }; isPaused ? resume() : pause() }

    /// Freezes the flight where it is and starts the crash sequence.
    func beginCrash() {
        guard crashStart == nil else { return }
        let t = Date()
        clock.pause(at: t)
        now = t
        slowNow = t
        crashStart = t
    }

    func stop() {
        isStopped = true
        timer?.invalidate()
        timer = nil
    }

    /// Scene update interval: 10 Hz while climbing or descending (the view zooms), 5 Hz at cruise
    /// (the ground moves only a few points per second), 1 Hz when nothing on screen shows the scene.
    private var desiredInterval: TimeInterval {
        guard sceneViewers > 0 else { return 1 }
        if takeoffRunning || isPaused { return 1.0 / 5 }
        let c = FlightProfile.climbSeconds(duration: plan.track.flightSeconds)
        let e = elapsed
        return (e < c + 5 || e > plan.duration - c - 5) ? 1.0 / 10 : 1.0 / 5
    }

    private func retime() {
        guard !isStopped else { return }
        let want = desiredInterval
        guard want != interval || timer == nil else { return }
        interval = want
        timer?.invalidate()
        let t = Timer(timeInterval: want, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isStopped else { return }
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
