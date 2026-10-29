import AppKit
import ContrailCore
import MapKit
import SwiftUI
import UserNotifications

/// Landing notifications. The chime is played by the app, so notifications are silent.
@MainActor final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var asked = false

    func prepare() {
        guard !asked, Bundle.main.bundleIdentifier != nil else { return }
        asked = true
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert]) { _, _ in }
    }

    func landed(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}

/// Keeps the display awake during a flight.
@MainActor final class AwakeKeeper {
    private var token: NSObjectProtocol?
    func set(_ on: Bool) {
        if on, token == nil {
            token = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated],
                                                          reason: "Contrail flight in progress")
        } else if !on, let t = token {
            ProcessInfo.processInfo.endActivity(t)
            token = nil
        }
    }
}

/// Shows a SwiftUI view as a live desktop background on every display, below icons and windows.
@MainActor final class DesktopSceneController {
    private var windows: [NSWindow] = []
    private var makeContent: (() -> AnyView)?
    private var screenObserver: NSObjectProtocol?
    var isShowing: Bool { !windows.isEmpty }

    func show(_ content: @escaping () -> AnyView) {
        makeContent = content
        rebuild()
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if self?.isShowing == true { self?.rebuild() } }
            }
        }
    }

    func hide() {
        tearDown()
        makeContent = nil
    }

    /// Detach the SwiftUI content first so its views see themselves leave the window.
    private func tearDown() {
        for w in windows {
            w.contentView = nil
            w.orderOut(nil)
            w.close()
        }
        windows.removeAll()
    }

    private func rebuild() {
        tearDown()
        guard let makeContent else { return }
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.setFrame(screen.frame, display: false)
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.hasShadow = false
            w.isOpaque = true
            w.backgroundColor = .black
            w.title = "Contrail Desktop Scene"
            w.contentView = NSHostingView(rootView: makeContent())
            w.orderFront(nil)
            windows.append(w)
        }
    }
}

/// Optional: sets the real wallpaper to a still image of the route, and restores it afterwards.
@MainActor final class WallpaperSync {
    private var saved: [(screen: NSScreen, url: URL, options: [NSWorkspace.DesktopImageOptionKey: Any])] = []
    private(set) var disabledByHang = false
    private let dir: URL

    init(dir: URL) { self.dir = dir }

    func apply(for plan: FlightPlan) async {
        guard !disabledByHang else { return }
        let opts = MKMapSnapshotter.Options()
        let mid = Geo.interpolate(plan.origin.coordinate, plan.destination.coordinate, fraction: 0.5)
        let span = min(140, max(1.5, plan.distanceKm / 111 * 1.4))
        opts.region = MKCoordinateRegion(center: mid.cl, span: MKCoordinateSpan(latitudeDelta: span * 0.62, longitudeDelta: span))
        opts.size = NSSize(width: 2560, height: 1600)
        opts.preferredConfiguration = MKImageryMapConfiguration()
        guard let shot = try? await MKMapSnapshotter(options: opts).start() else { return }
        let img = NSImage(size: shot.image.size)
        img.lockFocus()
        shot.image.draw(at: .zero, from: .zero, operation: .copy, fraction: 1)
        NSColor.black.withAlphaComponent(0.3).setFill()
        NSRect(origin: .zero, size: shot.image.size).fill(using: .sourceOver)
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let url = dir.appendingPathComponent("wallpaper-\(UUID().uuidString.prefix(8)).png")
        do { try png.write(to: url) } catch { return }
        if saved.isEmpty {
            saved = NSScreen.screens.compactMap { s in
                guard let u = NSWorkspace.shared.desktopImageURL(for: s) else { return nil }
                return (s, u, NSWorkspace.shared.desktopImageOptions(for: s) ?? [:])
            }
        }
        for s in NSScreen.screens where !(await set(url, [:], s)) { disabledByHang = true; break }
    }

    func restore() async {
        for item in saved { _ = await set(item.url, item.options, item.screen) }
        saved.removeAll()
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in files where f.lastPathComponent.hasPrefix("wallpaper-") { try? FileManager.default.removeItem(at: f) }
        }
    }

    /// Runs the wallpaper call off the main thread with a 5 s limit, because it can hang.
    private func set(_ url: URL, _ options: [NSWorkspace.DesktopImageOptionKey: Any], _ screen: NSScreen) async -> Bool {
        nonisolated(unsafe) let s = screen
        nonisolated(unsafe) let o = options
        return await withCheckedContinuation { cont in
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .utility).async {
                try? NSWorkspace.shared.setDesktopImageURL(url, for: s, options: o)
                done.signal()
            }
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: done.wait(timeout: .now() + 5) == .success)
            }
        }
    }
}
