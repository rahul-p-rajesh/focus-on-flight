import ContrailCore
import MapKit
import SwiftUI

/// The moving satellite scene: map camera on the plane, heading-up, with plane and contrails.
/// Used in the main window and, in desktop mode, behind everything on each display.
struct FlightSceneView: View {
    let session: FlightSession
    let model: AppModel
    var isDesktop = false
    var showGlobe = false

    @State private var position: MapCameraPosition = .automatic
    @State private var didStartTakeoff = false
    @State private var counted = false

    var body: some View {
        ZStack {
            Map(position: $position, interactionModes: []) {
                if showGlobe {
                    MapPolyline(coordinates: session.plan.path.map(\.cl))
                        .stroke(Theme.accent.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 6]))
                    Annotation("", coordinate: session.position.cl) {
                        Image(systemName: "airplane")
                            .font(.system(size: 18, weight: .semibold))
                            .rotationEffect(.degrees(session.heading - 90))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 4)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(Self.style(labels: session.plan.mapLabels))
            .mapControls {}
            .overlay { SceneTint(strength: showGlobe ? 0.5 : 1).allowsHitTesting(false) }

            if !showGlobe {
                PlaneWithContrails(session: session, smooth: model.settings.smoothMotion).allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .background(OcclusionReader { setVisible($0) })
        .onAppear {
            if session.takeoffRunning { runTakeoff() } else { updateCamera(animated: false) }
        }
        .onDisappear { setVisible(false) }
        .onChange(of: session.now) { if !session.takeoffRunning { updateCamera(animated: true) } }
        .onChange(of: session.takeoffRunning) { if !session.takeoffRunning { updateCamera(animated: false) } }
        .onChange(of: showGlobe) { withAnimation(.easeInOut(duration: 1.6)) { position = .camera(camera()) } }
    }

    /// Satellite imagery, with town names, roads and airports when labels are on.
    static func style(labels: Bool) -> MapStyle {
        let elevation: MapStyle.Elevation = LaunchFlags.has("--flat") ? .flat : .realistic
        return labels
            ? .hybrid(elevation: elevation, pointsOfInterest: .including([.airport]), showsTraffic: false)
            : .imagery(elevation: elevation)
    }

    private func camera() -> MapCamera {
        if showGlobe {
            let km = session.plan.distanceKm
            return MapCamera(centerCoordinate: session.position.cl, distance: min(22_000_000, max(1_800_000, km * 1000 * 2.6)),
                             heading: 0, pitch: 0)
        }
        return MapCamera(centerCoordinate: session.position.cl, distance: session.altitude, heading: session.heading, pitch: 0)
    }

    /// Each tick moves the camera to where the plane is now. Animating that move over one tick lets
    /// MapKit glide between positions instead of stepping, which removes the jitter.
    private func updateCamera(animated: Bool) {
        if animated, !showGlobe, model.settings.smoothMotion, session.tickInterval < 0.5 {
            withAnimation(.linear(duration: session.tickInterval)) { position = .camera(camera()) }
        } else {
            position = .camera(camera())
        }
    }

    /// Counts this view towards the fast scene timer only while its window is actually visible.
    private func setVisible(_ seen: Bool) {
        let visible = seen || LaunchFlags.has("--force-visible") // test-only
        if visible, !counted { counted = true; session.sceneViewers += 1; updateCamera(animated: false) }
        else if !visible, counted { counted = false; session.sceneViewers -= 1 }
    }

    /// Globe view of the departure, then a long ease down to the runway; the climb follows.
    private func runTakeoff() {
        guard !didStartTakeoff else { return }
        didStartTakeoff = true
        let origin = session.plan.origin.coordinate.cl
        position = .camera(MapCamera(centerCoordinate: origin, distance: 9_000_000, heading: 0, pitch: 0))
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard session.takeoffRunning else { return }
            withAnimation(.easeInOut(duration: 4.2)) {
                position = .camera(MapCamera(centerCoordinate: origin, distance: FlightProfile.groundAltitudeM,
                                             heading: session.heading, pitch: 0))
            }
            try? await Task.sleep(for: .milliseconds(4500))
            session.takeoffRunning = false
        }
    }
}

/// Light tint and soft vignette. The bottom-left corner stays clear so the Apple Maps logo and Legal link remain visible.
struct SceneTint: View {
    var strength = 1.0
    var body: some View {
        GeometryReader { geo in
            let m = max(geo.size.width, geo.size.height)
            ZStack {
                Color.black.opacity(0.16 * strength)
                RadialGradient(colors: [.clear, .black.opacity(0.48 * strength)], center: .center,
                               startRadius: m * 0.28, endRadius: m * 0.8)
            }
            .mask {
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                    RoundedRectangle(cornerRadius: 18).frame(width: 190, height: 40).blur(radius: 14).blendMode(.destinationOut)
                }
                .compositingGroup()
            }
        }
    }
}

/// The airliner with two contrails of puffs drifting back at the speed the ground moves on screen.
/// Redrawn up to 30 times a second so the puffs and lights move smoothly.
struct PlaneWithContrails: View {
    let session: FlightSession
    var smooth = true

    var body: some View {
        TimelineView(.animation(minimumInterval: smooth ? 1.0 / 30 : 1.0 / 5, paused: session.isPaused)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let k = session.climbProgress
                // Ground speed on screen: about 236 m/s across a view roughly as tall as the camera is high.
                let speed = session.isPaused ? 0 : 236 / max(session.altitude, 1) * geo.size.height * 0.9
                PlaneScene(climb: k, time: t, groundSpeed: speed)
            }
        }
    }
}

/// Plane and contrails for one moment. Shared by the live scene and the offscreen preview.
struct PlaneScene: View {
    /// 0 on the ground, 1 at cruise.
    let climb: Double
    let time: TimeInterval
    /// Points per second the ground moves down the screen.
    let groundSpeed: Double

    var body: some View {
        GeometryReader { geo in
            let trail = Self.smooth((climb - 0.4) / 0.5)
            let span = 76 * (1 + (1 - climb) * 0.5)
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            Canvas { ctx, size in
                guard trail > 0.01 else { return }
                let unit = span / 76
                let spacing = 3.2 * unit
                let travelled = time * groundSpeed
                let base = floor(travelled / spacing)
                let frac = travelled - base * spacing
                let count = Int(min(size.height * 0.42, 320) / spacing)
                for (side, ex) in [(-1.0, -0.19), (1.0, 0.19)] {
                    for i in 0..<count {
                        let tt = Double(i) / Double(count)
                        let n = base - Double(i) // stable id per puff, so its wobble travels with it
                        let y = c.y + span * 0.07 + Double(i) * spacing + frac
                        // Nearly straight trails that slowly widen and drift apart, with a faint ripple.
                        let wobble = (sin(n * 0.29 + side * 1.3) * tt * 0.7 + side * tt * 5) * unit
                        let r = (1.4 + tt * 4.2) * unit
                        let a = pow(1 - tt, 1.5) * 0.72 * trail
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x + ex * span + wobble - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: .color(.white.opacity(a)))
                    }
                }
            }
            .blur(radius: 1.1)
            AirlinerView(span: span, time: time).position(c)
        }
    }

    static func smooth(_ x: Double) -> Double { let v = min(1, max(0, x)); return v * v * (3 - 2 * v) }
}

/// Main-window flight screen: scene plus an auto-hiding glass HUD.
struct FlightView: View {
    let session: FlightSession
    @Bindable var model: AppModel
    @State private var lastMove = Date()
    @State private var confirmEnd = false

    private var hudVisible: Bool {
        session.isPaused || model.showSoundPanel || confirmEnd
            || session.slowNow.timeIntervalSince(lastMove) < model.settings.hudHideSeconds
    }

    var body: some View {
        ZStack {
            FlightSceneView(session: session, model: model, showGlobe: model.showGlobe)
                .contentShape(Rectangle())
                .onTapGesture {
                    if session.takeoffRunning { session.takeoffRunning = false }
                    lastMove = Date()
                }

            if session.takeoffRunning {
                VStack(spacing: 6) {
                    Text("Cleared for takeoff").font(.system(size: 22, weight: .semibold))
                    Text("\(session.plan.origin.code) → \(session.plan.destination.code) · click to skip").font(.system(size: 13)).foregroundStyle(Theme.dim)
                }
                .padding(.horizontal, 22).padding(.vertical, 14).glassPanel(radius: 18)
                .transition(.opacity)
            }

            if session.isPaused {
                Label("Paused", systemImage: "pause.fill").font(.system(size: 20, weight: .semibold))
                    .padding(.horizontal, 20).padding(.vertical, 12).glassPanel(radius: 16)
                    .offset(y: -120)
            }

            if !session.takeoffRunning && hudVisible {
                hud.transition(.opacity)
            }

            if let b = model.banner {
                VStack {
                    Text(b).font(.system(size: 14, weight: .medium)).padding(.horizontal, 18).padding(.vertical, 11).glassPanel(radius: 16)
                        .padding(.top, 70)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.5), value: session.takeoffRunning)
        .animation(.easeInOut(duration: 0.6), value: hudVisible)
        .onChange(of: session.takeoffRunning) { lastMove = Date().addingTimeInterval(4) }
        .onChange(of: model.hudWake) { lastMove = Date().addingTimeInterval(20) }
        .animation(.easeInOut(duration: 0.4), value: model.banner)
        .onContinuousHover { _ in lastMove = Date() }
        .onExitCommand { lastMove = Date() }
        .background {
            Button("Pause or resume") { model.togglePause(); lastMove = Date() }
                .keyboardShortcut(.space, modifiers: []).hidden()
        }
        .confirmationDialog("End this flight now?", isPresented: $confirmEnd) {
            Button("End flight", role: .destructive) { model.endEarly() }
            Button("Keep flying", role: .cancel) {}
        } message: {
            Text("Your focus time so far is saved to the logbook.")
        }
    }

    private var hud: some View {
        VStack {
            if !session.plan.goal.isEmpty {
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: model.category(session.plan.categoryID)?.colorHex ?? "#888")).frame(width: 8, height: 8)
                    Text(session.plan.goal).font(.system(size: 14, weight: .medium)).lineLimit(1)
                }
                .padding(.horizontal, 16).padding(.vertical, 9).frame(maxWidth: 560).glassPanel(radius: 18)
                .padding(.top, 18)
            }
            Spacer()
            FlightStatusCard(session: session, model: model)
                .frame(maxWidth: 600)
            HStack(spacing: 10) {
                GlassIconButton(symbol: session.isPaused ? "play.fill" : "pause.fill", label: session.isPaused ? "Resume (Space)" : "Pause (Space)") {
                    model.togglePause()
                }
                GlassIconButton(symbol: "globe.europe.africa", label: model.showGlobe ? "Back to the window seat" : "Show route on the globe", active: model.showGlobe) {
                    model.showGlobe.toggle()
                }
                SoundButton(model: model, isPrimary: true)
                GlassIconButton(symbol: model.settings.chimeOn ? "bell.fill" : "bell.slash", label: model.settings.chimeOn ? "Landing chime on" : "Landing chime off", active: model.settings.chimeOn) {
                    model.settings.chimeOn.toggle()
                }
                GlassIconButton(symbol: "menubar.dock.rectangle", label: "Desktop mode: fly behind your windows", active: model.desktopMode) {
                    model.toggleDesktopMode()
                }
                GlassIconButton(symbol: "xmark", label: "End flight early") { confirmEnd = true }
            }
            .padding(.top, 10).padding(.bottom, 22)
        }
        .padding(.horizontal, 24)
    }
}

/// Route progress, time left, current Pomodoro period and region.
struct FlightStatusCard: View {
    let session: FlightSession
    let model: AppModel
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(spacing: 10) {
                Text(session.plan.origin.code).font(.system(size: 13, weight: .semibold, design: .monospaced))
                ProgressTrack(progress: session.hudFraction)
                Text(session.plan.destination.code).font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
            if session.plan.schedule.enabled && session.segments.count > 1 {
                PomodoroBar(segments: session.segments, elapsed: session.hudElapsed, total: session.plan.duration)
            }
            HStack(alignment: .lastTextBaseline) {
                Text(TimeFormat.clock(session.hudRemaining))
                    .font(.system(size: compact ? 30 : 38, weight: .light, design: .monospaced))
                    .accessibilityLabel("Time remaining \(TimeFormat.clock(session.hudRemaining))")
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    if session.plan.schedule.enabled {
                        let pos = session.hudFocusPosition
                        Text(session.isOnBreak
                             ? "Break · \(TimeFormat.clock(session.hudSegmentRemaining)) left"
                             : "Focus \(pos.index) of \(pos.count) · \(TimeFormat.clock(session.hudSegmentRemaining)) left")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(session.isOnBreak ? Theme.accent : .white)
                    }
                    if !compact, let r = session.regionName {
                        Text("Over \(r)").font(.system(size: 12)).foregroundStyle(Theme.dim)
                    }
                    Text("Lands \(session.landingTime.formatted(date: .omitted, time: .shortened))").font(.system(size: 12)).foregroundStyle(Theme.dim)
                }
            }
        }
        .padding(compact ? 14 : 18)
        .glassPanel(radius: 22)
    }
}

struct ProgressTrack: View {
    let progress: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14)).frame(height: 3)
                Capsule().fill(Theme.accent).frame(width: max(0, g.size.width * progress), height: 3)
                Image(systemName: "airplane").font(.system(size: 11)).foregroundStyle(.white)
                    .position(x: max(6, min(g.size.width - 6, g.size.width * progress)), y: g.size.height / 2)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 14)
        .accessibilityElement().accessibilityLabel("Route progress \(Int(progress * 100)) percent")
    }
}

/// Small panel shown in the main window while the scene runs as the desktop background.
struct DesktopControlPanel: View {
    let session: FlightSession
    @Bindable var model: AppModel
    @State private var confirmEnd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(session.plan.goal).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer()
            }
            FlightStatusCard(session: session, model: model, compact: true)
            HStack(spacing: 8) {
                GlassIconButton(symbol: session.isPaused ? "play.fill" : "pause.fill", label: session.isPaused ? "Resume" : "Pause") { model.togglePause() }
                SoundButton(model: model, isPrimary: true)
                GlassIconButton(symbol: model.settings.chimeOn ? "bell.fill" : "bell.slash", label: "Landing chime", active: model.settings.chimeOn) { model.settings.chimeOn.toggle() }
                Spacer()
                Button("Back to window") { model.toggleDesktopMode() }.buttonStyle(SecondaryButtonStyle())
                GlassIconButton(symbol: "xmark", label: "End flight early") { confirmEnd = true }
            }
        }
        .padding(.horizontal, 14).padding(.top, 30).padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.06, green: 0.09, blue: 0.08))
        .background {
            Button("Pause or resume") { model.togglePause() }.keyboardShortcut(.space, modifiers: []).hidden()
        }
        .confirmationDialog("End this flight now?", isPresented: $confirmEnd) {
            Button("End flight", role: .destructive) { model.endEarly() }
            Button("Keep flying", role: .cancel) {}
        }
    }
}

/// One piece per focus block (white) and break (blue), sized by length, filling as the flight goes.
struct PomodoroBar: View {
    let segments: [PomodoroSchedule.Segment]
    /// Seconds into the flight. Pass 0 for a preview.
    let elapsed: TimeInterval
    let total: TimeInterval
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 3
            let usable = max(0, geo.size.width - gap * CGFloat(max(0, segments.count - 1)))
            HStack(spacing: gap) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    let w = usable * seg.length / max(total, 1)
                    let fill = min(1, max(0, (elapsed - seg.start) / max(seg.length, 1)))
                    let isBreak = seg.kind == .rest
                    ZStack(alignment: .leading) {
                        Capsule().fill(isBreak ? Theme.accent.opacity(0.22) : Color.white.opacity(0.14))
                        Capsule().fill(isBreak ? Theme.accent : Color.white.opacity(0.85)).frame(width: w * fill)
                    }
                    .frame(width: w)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Pomodoro plan: \(segments.filter { $0.kind == .focus }.count) focus blocks, \(segments.filter { $0.kind == .rest }.count) breaks")
    }
}
