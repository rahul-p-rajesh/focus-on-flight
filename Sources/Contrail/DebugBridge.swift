import AppKit
import ContrailCore
import Foundation
import MapKit
import SwiftUI

/// Test-only remote control, enabled with --debug-bridge DIR. Commands arrive as distributed
/// notifications named "contrail.debug" with the command string as the object. Snapshots of the
/// app's own windows are written to DIR. Never active in normal use.
@MainActor final class DebugBridge {
    static var shared: DebugBridge?
    let dir: URL
    weak var model: AppModel?
    private var observer: NSObjectProtocol?

    static func startIfRequested(_ model: AppModel) {
        guard shared == nil, let path = LaunchFlags.value("--debug-bridge") else { return }
        let b = DebugBridge(dir: URL(fileURLWithPath: path), model: model)
        shared = b
    }

    init(dir: URL, model: AppModel) {
        self.dir = dir
        self.model = model
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        observer = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("contrail.debug"), object: nil, queue: .main) { [weak self] n in
            let cmd = n.object as? String ?? ""
            MainActor.assumeIsolated { self?.handle(cmd) }
        }
        log("ready")
    }

    private func log(_ s: String) {
        let url = dir.appendingPathComponent("bridge.log")
        let line = "\(Date().formatted(.iso8601)) \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }

    private func handle(_ cmd: String) {
        guard let m = model else { return }
        let parts = cmd.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        switch parts.first ?? "" {
        case "snapshot": snapshot(arg)
        case "tab": m.tab = arg == "logbook" ? .logbook : arg == "settings" ? .settings : .fly
        case "mode": m.draft.mode = arg == "time" ? .time : .route
        case "minutes": m.draft.minutes = Double(arg) ?? 60; m.refreshSuggestions()
        case "shuffle": m.refreshSuggestions(shuffle: true)
        case "pickSuggestion": if let i = Int(arg), i < m.draft.suggestions.count { m.draft.destination = m.draft.suggestions[i].place }
        case "origin", "destination":
            if let a = m.airports.search(arg, limit: 1).first { m.setPlace(a.place, for: parts[0] == "origin" ? .origin : .destination) }
        case "point":
            // point:origin:lat,lon
            let p = arg.split(separator: ":"); if p.count == 2 {
                let ll = p[1].split(separator: ",").compactMap { Double($0) }
                if ll.count == 2 { Task { await m.pick(Coordinate(latitude: ll[0], longitude: ll[1]), for: p[0] == "origin" ? .origin : .destination); log("picked \(m.draft.origin?.name ?? "-") / \(m.draft.destination?.name ?? "-")") } }
            }
        case "goal": m.draft.goal = arg
        case "plan":
            if let pl = m.boardingPlan {
                let kmh = pl.distanceKm / max(pl.track.flightSeconds, 1) * 3600
                log(String(format: "plan flight=%.0fmin lands=%@ (%@) avgKmh=%.0f", pl.duration / 60, pl.destination.code, pl.destination.name, kmh))
            } else { log("plan none") }
        case "search":
            // search:origin:query — logs results and picks the first
            let p = arg.split(separator: ":", maxSplits: 1).map(String.init)
            if p.count == 2 {
                Task {
                    let rs = m.places.searchAirports(p[1]) + (await m.places.searchPlaces(p[1]))
                    log("results \(rs.prefix(6).map { "\($0.title) [\($0.subtitle)]" })")
                    if let r = rs.first { await m.choose(r, for: p[0] == "origin" ? .origin : .destination) }
                    log("chose \(m.draft.origin.map { "\($0.code) \($0.name) | \($0.locality ?? "-")" } ?? "-") / \(m.draft.destination.map { "\($0.code) \($0.name)" } ?? "-")")
                }
            }
        case "board": m.goToBoarding()
        case "takeoff": m.takeOff()
        case "skipTakeoff": m.flight?.takeoffRunning = false
        case "pause": m.togglePause()
        case "end": m.endEarly()
        case "desktop": m.toggleDesktopMode()
        case "globe": m.showGlobe.toggle()
        case "sound": m.soundPanelRequest += 1
        case "toggleLayer": if let l = (SoundMixer.ambience + SoundMixer.music).first(where: { $0.id == arg }) { m.sound.toggle(l) }
        case "master": m.sound.mix.masterOn.toggle()
        case "library": m.sound.toggleLibrary()
        case "state": log(state())
        case "previewHUD": previewHUD()
        case "smoothness": Task { await smoothness() }
        case "preview":
            // preview:name:lat,lon,altitudeM,heading,labels(0|1),elevation(flat|realistic)
            let p = arg.split(separator: ":", maxSplits: 1).map(String.init)
            if p.count == 2 { Task { await preview(name: p[0], spec: p[1]) } }
        case "wake": m.hudWake += 1
        case "minimize": m.mainWindow?.miniaturize(nil)
        case "hide": NSApp.hide(nil)
        case "unhide": NSApp.unhide(nil)
        case "restore": m.mainWindow?.deminiaturize(nil)
        case "quit": NSApp.terminate(nil)
        default: log("unknown \(cmd)")
        }
        log("ok \(cmd)")
    }

    private func state() -> String {
        guard let m = model else { return "" }
        var s = "stage=\(m.stage) tab=\(m.tab) desktop=\(m.desktopMode) records=\(m.records.count)"
        s += " mode=\(m.draft.mode.rawValue) origin=\(m.draft.origin?.code ?? "-") dest=\(m.draft.destination?.code ?? "-") suggestions=\(m.draft.suggestions.map { "\($0.place.code)\($0.place.isMadeUp ? "*" : "")/\(Int($0.minutes.rounded()))m" }.joined(separator: ","))"
        if let f = m.flight {
            s += String(format: " elapsed=%.1f remaining=%.1f frac=%.4f alt=%.0f heading=%.1f paused=%@ break=%@ takeoff=%@ viewers=%d region=%@",
                        f.elapsed, f.remaining, f.routeFraction, f.altitude, f.heading, "\(f.isPaused)", "false", "\(f.takeoffRunning)", f.sceneViewers, f.regionName ?? "-")
            s += String(format: " interval=%.2f lat=%.4f lon=%.4f", f.tickInterval, f.position.latitude, f.position.longitude)
        }
        s += " audio=[\(m.sound.debugState)]"
        s += " mix=\(m.settings.mix.active.sorted()) music=\(m.settings.mix.music ?? "-") master=\(m.settings.mix.masterOn)"
        s += " windows=\(NSApp.windows.filter(\.isVisible).map { "\($0.title)@\(Int($0.level.rawValue)):\(Int($0.frame.width))x\(Int($0.frame.height))" })"
        return s
    }

    /// Renders a still of the flight scene offscreen: MapKit snapshot + tint + plane + contrails.
    private func preview(name: String, spec: String) async {
        let v = spec.split(separator: ",").map(String.init)
        guard v.count >= 6, let lat = Double(v[0]), let lon = Double(v[1]), let alt = Double(v[2]), let heading = Double(v[3]) else {
            log("bad preview spec"); return
        }
        let labels = v[4] == "1"
        let elevation: MKMapConfiguration.ElevationStyle = v[5] == "flat" ? .flat : .realistic
        let size = NSSize(width: 1300, height: 840)
        let o = MKMapSnapshotter.Options()
        o.camera = MKMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: lat, longitude: lon), fromDistance: alt, pitch: 0, heading: heading)
        o.size = size
        if labels {
            let h = MKHybridMapConfiguration(elevationStyle: elevation)
            h.pointOfInterestFilter = MKPointOfInterestFilter(including: [.airport])
            o.preferredConfiguration = h
        } else {
            o.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: elevation)
        }
        guard let shot = try? await MKMapSnapshotter(options: o).start() else { log("preview snapshot failed"); return }
        let view = ZStack {
            Image(nsImage: shot.image).resizable()
            // Approximate the route line (the snapshotter cannot draw map overlays).
            Rectangle().fill(.white.opacity(0.32)).frame(width: 1.6)
            SceneTint()
            PlaneScene(climb: 1, time: 3.3, groundSpeed: 20)
        }
        .frame(width: size.width, height: size.height)
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.cgImage else { log("preview render failed"); return }
        let url = dir.appendingPathComponent("\(name)-preview.png")
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: url)
        let raw = dir.appendingPathComponent("\(name)-raw.png")
        if let cg = shot.image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: raw)
        }
        log("preview \(url.lastPathComponent)")
    }

    /// Renders the flight status card for a sample flight 40 minutes in, offscreen.
    private func previewHUD() {
        guard let m = model, let a = m.airports.search("ORD", limit: 1).first, let b = m.airports.search("DEN", limit: 1).first,
              let cat = m.activeCategories.first else { return }
        let plan = FlightPlan(origin: a.place, destination: b.place, seat: "12A", categoryID: cat.id, goal: "Preview")
        let s = FlightSession(plan: plan, now: Date().addingTimeInterval(-40 * 60))
        s.stop()
        let view = FlightStatusCard(session: s, model: m).frame(width: 600).padding(30)
            .background(Color(red: 0.2, green: 0.25, blue: 0.2)).environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.cgImage else { log("hud render failed"); return }
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("hud-preview.png"))
        log("hud preview written")
    }

    /// Samples the flight map's camera centre at 60 Hz for 3 s and reports how even the per-frame movement is.
    /// Smooth motion: steady steps (low variation, no zero frames). Stepping: many zero frames and spikes.
    private func smoothness() async {
        func find(_ v: NSView) -> MKMapView? {
            if let m = v as? MKMapView { return m }
            for s in v.subviews { if let m = find(s) { return m } }
            return nil
        }
        // Prefer a desktop-scene window (not managed by Stage Manager), else the main window.
        let windows = NSApp.windows.filter(\.isVisible).sorted { $0.level.rawValue < $1.level.rawValue }
        guard let map = windows.lazy.compactMap({ $0.contentView.flatMap(find) }).first else { log("no map view"); return }
        var steps: [Double] = []
        var last = map.camera.centerCoordinate
        for _ in 0..<180 {
            try? await Task.sleep(for: .milliseconds(16))
            let c = map.camera.centerCoordinate
            steps.append(CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude)))
            last = c
        }
        let mean = steps.reduce(0, +) / Double(steps.count)
        let sd = sqrt(steps.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(steps.count))
        let zeros = steps.filter { $0 < mean * 0.05 }.count
        log(String(format: "smoothness mean=%.2fm/frame cv=%.2f zeroFrames=%d/%d max=%.2fm", mean, mean > 0 ? sd / mean : 0, zeros, steps.count, steps.max() ?? 0))
    }

    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// Captures each visible window of this app to DIR/name-N.png.
    private func snapshot(_ name: String) {
        let fn: CreateImage? = {
            guard let h = dlopen(nil, RTLD_NOW), let sym = dlsym(h, "CGWindowListCreateImage") else { return nil }
            return unsafeBitCast(sym, to: CreateImage.self)
        }()
        for (i, w) in NSApp.windows.filter({ $0.isVisible && $0.frame.width > 100 }).enumerated() {
            var image: CGImage?
            if let fn {
                // kCGWindowListOptionIncludingWindow = 8, kCGWindowImageBoundsIgnoreFraming = 1
                image = fn(.null, 8, UInt32(w.windowNumber), 1)?.takeRetainedValue()
            }
            if image == nil, let v = w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                image = rep.cgImage
            }
            guard let img = image else { log("snapshot failed for window \(i)"); continue }
            let rep = NSBitmapImageRep(cgImage: img)
            let url = dir.appendingPathComponent("\(name)-\(i).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            log("snapshot \(url.lastPathComponent) \(img.width)x\(img.height) level=\(w.level.rawValue)")
        }
    }
}
