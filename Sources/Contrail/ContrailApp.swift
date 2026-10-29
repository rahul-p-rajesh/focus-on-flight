import AppKit
import ContrailCore
import SwiftUI

@main
struct ContrailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Contrail", id: "main") {
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
                Image(systemName: "airplane")
                Text(TimeFormat.clock(f.hudRemaining))
            } else {
                Image(systemName: "airplane")
            }
        }
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
        Button("Show Contrail") { model.showMainWindow() }
        Button("Quit Contrail") { NSApp.terminate(nil) }.keyboardShortcut("q")
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
