import AppKit
import ContrailCore
import Foundation
import Observation
import SwiftUI

enum PlanMode: String, CaseIterable, Identifiable {
    case route = "By route", time = "By time"
    var id: String { rawValue }
}

enum PickTarget { case origin, destination }

@Observable @MainActor final class FlightDraft {
    var mode: PlanMode = .route
    var origin: Place?
    var destination: Place?
    var minutes: Double = 60
    /// Study time chosen for a route. nil means "use the route's flight time" (the prefill).
    var studyMinutes: Double?
    var suggestions: [DestinationCandidate] = []
    var suggestionsLoading = false
    var suggestionsWidened = false
    var suggestionRotation = 0.0
    var categoryID: UUID?
    var goal = ""
    var picking: PickTarget?
    var seat = "14A"
}

@Observable @MainActor final class AppModel {
    enum Tab: Hashable { case fly, logbook, settings }
    enum Stage: Equatable { case planning, boarding, flying, landed }

    var tab: Tab = .fly
    var stage: Stage = .planning
    let draft = FlightDraft()
    private(set) var flight: FlightSession?
    var lastRecord: FlightRecord?
    var desktopMode = false
    var showGlobe = false
    /// Bumped to show the flight HUD, as if the mouse had moved.
    var hudWake = 0
    /// Bumped by the menu command to open or close the sound panel on the primary sound button.
    var soundPanelRequest = 0
    var showSoundPanel = false { didSet { sound.previewing = showSoundPanel && stage != .flying } }
    var banner: String?
    var reduceMotion = false
    weak var mainWindow: NSWindow?

    var settings: AppSettings { didSet { if settings != oldValue { store.save("settings", settings); syncMix() } } }
    var categories: [FocusCategory] { didSet { store.save("categories", categories) } }
    var records: [FlightRecord] { didSet { store.save("logbook", records) } }
    var library: [MusicTrack] { didSet { store.save("library", library); sound.library = library } }

    let store: Store
    let airports: AirportIndex
    let places: PlaceService
    let sound: SoundMixer
    let location = LocationFetcher()
    private let notifier = Notifier()
    private let awake = AwakeKeeper()
    private let desktop = DesktopSceneController()
    private let wallpaper: WallpaperSync
    private var savedWindowFrame: NSRect?
    private var lastRegionLookup = Date.distantPast
    private var lastSegmentKind: PomodoroSchedule.Kind?
    private var bannerTask: Task<Void, Never>?
    private var suggestionTask: Task<Void, Never>?
    let timeScale: Double

    init() {
        let store = Store()
        self.store = store
        let settings = store.load("settings", default: AppSettings())
        self.settings = settings
        var cats = store.load("categories", default: FocusCategory.defaults)
        if cats.isEmpty { cats = FocusCategory.defaults }
        self.categories = cats
        self.records = store.load("logbook", default: [FlightRecord]())
        self.library = store.load("library", default: [MusicTrack]())
        if let url = AppResources.url("airports", "json"), let idx = try? AirportIndex.load(from: url) {
            airports = idx
        } else {
            NSLog("Contrail: airports.json not found; airport names are unavailable")
            airports = AirportIndex(airports: [])
        }
        places = PlaceService(airports: airports)
        sound = SoundMixer(mix: settings.mix)
        wallpaper = WallpaperSync(dir: store.dir)
        timeScale = Double(LaunchFlags.value("--time-scale") ?? "") ?? 1
        sound.library = library
        sound.onMixChange = { [weak self] mix in
            guard let self, self.settings.mix != mix else { return }
            self.settings.mix = mix
        }
        draft.categoryID = activeCategories.first?.id
        desktopMode = settings.desktopModeByDefault
        if LaunchFlags.has("--seed-logbook"), LaunchFlags.value("--data-dir") != nil, records.isEmpty { seedLogbook() }
    }

    private func syncMix() { if sound.mix != settings.mix { sound.mix = settings.mix } }

    // MARK: Categories

    var activeCategories: [FocusCategory] { categories.filter { !$0.archived } }
    func category(_ id: UUID?) -> FocusCategory? { categories.first { $0.id == id } }

    // MARK: Planning

    var draftDistanceKm: Double? {
        guard let o = draft.origin, let d = draft.destination else { return nil }
        return Geo.distanceKm(o.coordinate, d.coordinate)
    }

    var draftMinutes: Double? { draftDistanceKm.map { FlightTiming.minutes(forDistanceKm: $0) } }

    /// Route flight time rounded to 5 minutes: the prefilled study time.
    var routeStudyMinutes: Double? { draftMinutes.map { max(15, ($0 / 5).rounded() * 5) } }

    /// Study time that will be used: the user's choice, else the prefill. In "By time" mode, the slider.
    var effectiveStudyMinutes: Double? {
        if draft.mode == .time { return draft.destination == nil ? nil : draft.minutes }
        return draft.studyMinutes ?? routeStudyMinutes
    }

    /// Whole journey with breaks, in minutes.
    var journeyMinutes: Double? { effectiveStudyMinutes.map { settings.pomodoro.duration(forFocus: $0 * 60) / 60 } }

    var routeProblem: String? {
        guard let d = draftDistanceKm else { return nil }
        if d < FlightTiming.minimumDistanceKm { return "Pick places at least 50 km apart." }
        return nil
    }

    var routeWarning: String? {
        guard let m = journeyMinutes, m > FlightTiming.longFlightWarningMinutes else { return nil }
        return "This is a long session (\(TimeFormat.duration(minutes: m))). You can end it early at any time."
    }

    var canContinue: Bool {
        draft.origin != nil && draft.destination != nil && routeProblem == nil && draft.categoryID != nil
            && !draft.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func setPlace(_ p: Place, for target: PickTarget) {
        switch target {
        case .origin:
            draft.origin = p
            if draft.mode == .time { draft.destination = nil; refreshSuggestions() }
        case .destination:
            draft.destination = p
        }
        draft.studyMinutes = nil // a new route prefills its own study time
    }

    func choose(_ r: PlaceResult, for target: PickTarget) async {
        setPlace(await places.resolve(r), for: target)
    }

    func pick(_ c: Coordinate, for target: PickTarget) async {
        draft.picking = nil
        setPlace(await places.resolve(c), for: target)
    }

    /// Returns false when location is unavailable.
    func useCurrentLocation(for target: PickTarget) async -> Bool {
        guard let loc = await location.current() else { return false }
        setPlace(await places.resolve(Coordinate(loc.coordinate)), for: target)
        return true
    }

    func refreshSuggestions(shuffle: Bool = false) {
        guard draft.mode == .time, let origin = draft.origin else { draft.suggestions = []; return }
        if shuffle { draft.suggestionRotation = Double.random(in: 3...12) + draft.suggestionRotation }
        suggestionTask?.cancel()
        draft.suggestionsLoading = true
        let minutes = draft.minutes, rotation = draft.suggestionRotation
        suggestionTask = Task {
            try? await Task.sleep(for: .milliseconds(250)) // debounce slider drags
            guard !Task.isCancelled else { return }
            let result = await places.suggestions(origin: origin.coordinate, minutes: minutes, rotation: rotation)
            guard !Task.isCancelled else { return }
            draft.suggestions = result.picks
            draft.suggestionsWidened = result.widened
            draft.suggestionsLoading = false
            if let d = draft.destination, !result.picks.contains(where: { $0.place == d }) { draft.destination = nil }
        }
    }

    func goToBoarding() {
        guard canContinue else { return }
        var g = SystemRandomNumberGenerator()
        draft.seat = Seat.randomWindow(using: &g)
        stage = .boarding
    }

    func backToPlanning() { stage = .planning }

    var boardingPlan: FlightPlan? {
        guard let o = draft.origin, let d = draft.destination, let c = draft.categoryID else { return nil }
        var plan = FlightPlan(origin: o, destination: d, schedule: settings.pomodoro, seat: draft.seat, categoryID: c,
                              goal: draft.goal.trimmingCharacters(in: .whitespacesAndNewlines),
                              studyMinutes: effectiveStudyMinutes, timeScale: timeScale)
        plan.cruiseAltitude = settings.cruiseAltitude.metres
        plan.mapLabels = settings.mapLabels
        return plan
    }

    // MARK: Flight

    func takeOff() {
        guard let plan = boardingPlan else { return }
        let session = FlightSession(plan: plan)
        session.takeoffRunning = !reduceMotion
        session.onTick = { [weak self] s in self?.tick(s) }
        flight = session
        lastSegmentKind = session.segment?.kind
        lastRegionLookup = .distantPast
        stage = .flying
        tab = .fly
        showSoundPanel = false
        showGlobe = false
        sound.setFlightActive(true, fade: 4)
        awake.set(settings.keepAwake)
        notifier.prepare()
        if desktopMode { enterDesktop() }
        if settings.wallpaperSync {
            Task { await wallpaper.apply(for: plan); if wallpaper.disabledByHang { settings.wallpaperSync = false; show("Wallpaper sync was turned off because macOS stopped responding to it.") } }
        }
    }

    private func tick(_ s: FlightSession) {
        if s.isFinished { finish(.landed); return }
        let kind = s.segment?.kind
        if s.plan.schedule.enabled, kind != lastSegmentKind {
            if kind == .rest { show("Seatbelt sign off. Stand up and stretch for \(Int(s.plan.schedule.breakMinutes * timeScale)) minutes.") }
            else if lastSegmentKind == .rest { show("Seatbelt sign on. Back to your goal.") }
            lastSegmentKind = kind
        }
        if sound.ducked != s.isOnBreak { sound.ducked = s.isOnBreak }
        if Date().timeIntervalSince(lastRegionLookup) > 120 {
            lastRegionLookup = Date()
            let pos = s.position
            Task { if let name = await places.regionName(at: pos) { s.regionName = name } }
        }
    }

    func togglePause() { flight?.togglePause() }

    func endEarly() { finish(.endedEarly) }

    private func finish(_ outcome: FlightOutcome) {
        guard let s = flight else { return }
        s.stop()
        let plan = s.plan
        let rec = FlightRecord(
            startedAt: s.startedAt, endedAt: Date(), origin: plan.origin, destination: plan.destination,
            distanceKm: plan.distanceKm, plannedSeconds: plan.duration * timeScale, flownSeconds: s.elapsed * timeScale,
            focusSeconds: s.focusElapsed * timeScale, breakCount: s.breaksTaken, categoryID: plan.categoryID,
            goal: plan.goal, seat: plan.seat, outcome: outcome)
        if outcome == .landed || s.elapsed >= 60 / timeScale { records.append(rec) }
        lastRecord = rec
        sound.setFlightActive(false, fade: 3)
        sound.ducked = false
        if outcome == .landed {
            if settings.chimeOn { sound.playChime() }
            let cat = category(plan.categoryID)?.name ?? "focus"
            notifier.landed(title: "Landed at \(plan.destination.name)",
                            body: "\(Int((rec.focusSeconds / 60).rounded())) min of \(cat). Goal: \(plan.goal)")
        }
        awake.set(false)
        if desktop.isShowing { exitDesktop() }
        if settings.wallpaperSync { Task { await wallpaper.restore() } }
        flight = nil
        stage = .landed
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func planNext(continueJourney: Bool) {
        if continueJourney, let r = lastRecord { draft.origin = r.destination }
        draft.destination = nil
        draft.studyMinutes = nil
        draft.goal = ""
        draft.suggestions = []
        stage = .planning
        if draft.mode == .time { refreshSuggestions() }
    }

    func setGoalDone(_ id: UUID, _ done: Bool) {
        if let i = records.firstIndex(where: { $0.id == id }) { records[i].goalDone = done }
        if lastRecord?.id == id { lastRecord?.goalDone = done }
    }

    // MARK: Desktop mode

    func toggleDesktopMode() {
        desktopMode.toggle()
        guard stage == .flying else { return }
        desktopMode ? enterDesktop() : exitDesktop()
    }

    private func enterDesktop() {
        guard let s = flight else { return }
        desktopMode = true
        desktop.show { [unowned self] in AnyView(FlightSceneView(session: s, model: self, isDesktop: true)) }
        if let w = mainWindow, let screen = w.screen ?? NSScreen.main {
            savedWindowFrame = w.frame
            let size = NSSize(width: 380, height: 236)
            let vf = screen.visibleFrame
            w.setFrame(NSRect(x: vf.maxX - size.width - 24, y: vf.maxY - size.height - 24, width: size.width, height: size.height),
                       display: true, animate: !reduceMotion)
        }
    }

    private func exitDesktop() {
        desktop.hide()
        if let w = mainWindow, let f = savedWindowFrame {
            w.setFrame(f, display: true, animate: !reduceMotion)
            savedWindowFrame = nil
        }
    }

    func showMainWindow() {
        NSApp.activate()
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Messages

    func show(_ message: String) {
        banner = message
        bannerTask?.cancel()
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { banner = nil }
        }
    }

    func appWillTerminate() {
        if flight != nil { finish(.endedEarly) }
        if settings.wallpaperSync {
            let sem = DispatchSemaphore(value: 0)
            Task { await wallpaper.restore(); sem.signal() }
            _ = sem.wait(timeout: .now() + 3)
        }
    }

    // MARK: Test data

    private func seedLogbook() {
        guard airports.airports.count > 10 else { return }
        var rng = SystemRandomNumberGenerator()
        let cats = activeCategories
        var out: [FlightRecord] = []
        for day in 0..<21 {
            for _ in 0..<Int.random(in: 0...3, using: &rng) {
                let a = airports.airports.randomElement(using: &rng)!.place
                let b = airports.airports.randomElement(using: &rng)!.place
                let mins = Double.random(in: 25...120, using: &rng)
                let start = Calendar.current.date(byAdding: .day, value: -day, to: Date())!.addingTimeInterval(-Double.random(in: 0...30000, using: &rng))
                out.append(FlightRecord(startedAt: start, endedAt: start.addingTimeInterval(mins * 60), origin: a, destination: b,
                                        distanceKm: Geo.distanceKm(a.coordinate, b.coordinate), plannedSeconds: mins * 60,
                                        flownSeconds: mins * 60, focusSeconds: mins * 50, breakCount: Int(mins / 30),
                                        categoryID: cats.randomElement(using: &rng)!.id, goal: ["Draft chapter", "Fix bug", "Read paper", "Plan sprint"].randomElement(using: &rng)!,
                                        goalDone: Bool.random(using: &rng), seat: "12A", outcome: .landed))
            }
        }
        records = out
    }
}
