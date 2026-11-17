import AppKit
import ContrailCore
import SwiftUI

@main
struct ContrailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    init() { MenuBarPlacement.startNearRight() }

    var body: some Scene {
        Window("Focus on Flight", id: "main") {
            RootView(model: model)
                .onAppear { delegate.model = model }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Go") {
                Button("Fly") { model.tab = .fly }.keyboardShortcut("1")
                Button("Logbook") { model.tab = .logbook }.keyboardShortcut("l")
                Button("Settings") { model.tab = .settings }.keyboardShortcut(",")
            }
            CommandMenu("Flight") {
                Button(model.flight?.isPaused == true ? "Resume" : "Pause") { model.togglePause() }.disabled(model.flight == nil)
                Button(model.desktopMode ? "Leave Desktop Mode" : "Desktop Mode") { model.toggleDesktopMode() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Sound…") { model.soundPanelRequest += 1 }.keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("End Flight Early") { model.endEarly() }.disabled(model.flight == nil)
            }
        }

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            if let f = model.flight {
                Image(nsImage: MenuBarIcon.image)
                Text(TimeFormat.clock(f.hudRemaining))
            } else {
                Image(nsImage: MenuBarIcon.image)
            }
        }
    }
}

/// macOS hides menu bar items that don't fit beside the camera notch, and a new item starts at the
/// far left, so on a full menu bar the travel time ends up hidden. Start it near the right, next to
/// Control Centre. Once the user Cmd-drags it elsewhere, macOS stores that position and this leaves it alone.
enum MenuBarPlacement {
    /// The menu bar item's autosave name; SwiftUI names the first MenuBarExtra "Item-0".
    static let key = "NSStatusItem Preferred Position Item-0"

    static func startNearRight() {
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        UserDefaults.standard.set(260.0, forKey: key) // points from the right edge of the screen
    }
}

struct MenuBarContent: View {
    @Bindable var model: AppModel
    var body: some View {
        if let f = model.flight {
            Text("\(f.plan.origin.code) → \(f.plan.destination.code) · \(TimeFormat.clock(f.hudRemaining)) left")
            Divider()
            Button(f.isPaused ? "Resume" : "Pause") { model.togglePause() }
            Button(model.desktopMode ? "Leave desktop mode" : "Desktop mode") { model.toggleDesktopMode() }
            Button(model.settings.mix.masterOn ? "Sound off" : "Sound on") { model.sound.mix.masterOn.toggle() }
            Button(model.settings.chimeOn ? "Landing chime off" : "Landing chime on") { model.settings.chimeOn.toggle() }
            Divider()
            Button("End flight early") { model.endEarly() }
        } else {
            Text("No flight in progress")
        }
        Divider()
        Button("Show Focus on Flight") { model.showMainWindow() }
        Button("Quit Focus on Flight") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @MainActor func applicationWillTerminate(_ notification: Notification) {
        model?.appWillTerminate()
    }
}
