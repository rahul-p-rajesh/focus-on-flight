import ContrailCore
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if model.stage == .flying, let s = model.flight {
                if model.desktopMode {
                    DesktopControlPanel(session: s, model: model)
                } else {
                    FlightView(session: s, model: model)
                        .transition(.opacity)
                }
            } else {
                ground
            }
        }
        .frame(minWidth: compact ? 340 : 960, minHeight: compact ? 200 : 620)
        .background(Color(red: 0.05, green: 0.07, blue: 0.06))
        .background(WindowAccessor { model.mainWindow = $0 })
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: model.stage)
        .onAppear {
            model.reduceMotion = reduceMotion
            DemoDriver.run(model)
            DebugBridge.startIfRequested(model)
        }
        .onChange(of: reduceMotion) { model.reduceMotion = reduceMotion }
    }

    private var compact: Bool { model.stage == .flying && model.desktopMode }

    private var ground: some View {
        ZStack(alignment: .top) {
            PlanningMap(model: model)
            if model.tab != .fly {
                SceneTint(strength: 1.1).ignoresSafeArea().allowsHitTesting(false)
            }
            Group {
                switch model.tab {
                case .fly:
                    switch model.stage {
                    case .boarding:
                        BoardingPassView(model: model)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    case .landed:
                        LandedView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
                    default:
                        HStack(alignment: .top) {
                            PlanPanel(model: model, draft: model.draft)
                            Spacer()
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.leading, 22).padding(.top, 68).padding(.bottom, 22)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                case .logbook:
                    LogbookView(model: model).padding(.top, 68).padding(.horizontal, 30).padding(.bottom, 24)
                case .settings:
                    SettingsView(model: model).padding(.top, 68).padding(.horizontal, 30).padding(.bottom, 24)
                }
            }
            topBar
            if let b = model.banner {
                Text(b).font(.system(size: 13, weight: .medium)).padding(.horizontal, 16).padding(.vertical, 10).glassPanel(radius: 14)
                    .padding(.top, 64)
                    .transition(.opacity)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()
            HStack(spacing: 2) {
                tabButton("Fly", .fly, "airplane")
                tabButton("Logbook", .logbook, "book.closed")
                tabButton("Settings", .settings, "gearshape")
            }
            .padding(4)
            .glassPanel(radius: 20, interactive: true)
            Spacer()
        }
        .overlay(alignment: .trailing) {
            SoundButton(model: model, isPrimary: true).padding(.trailing, 20)
        }
        .padding(.top, 14)
    }

    private func tabButton(_ title: String, _ tab: AppModel.Tab, _ symbol: String) -> some View {
        Button { model.tab = tab } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(model.tab == tab ? .white.opacity(0.16) : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Developer flags for testing: --demo-route LHR,MAN  --demo-stage boarding|flight|landed  --tab logbook|settings
@MainActor enum DemoDriver {
    static var done = false
    static func run(_ model: AppModel) {
        guard !done else { return }
        done = true
        if let tab = LaunchFlags.value("--tab") { model.tab = tab == "logbook" ? .logbook : tab == "settings" ? .settings : .fly }
        if LaunchFlags.has("--demo-time-mode") {
            model.draft.mode = .time
            if let code = LaunchFlags.value("--demo-route")?.split(separator: ",").first,
               let a = model.airports.search(String(code), limit: 1).first {
                model.draft.origin = a.place
                model.draft.minutes = Double(LaunchFlags.value("--demo-minutes") ?? "") ?? 60
                model.refreshSuggestions()
            }
            return
        }
        guard let route = LaunchFlags.value("--demo-route") else { return }
        let codes = route.split(separator: ",").map(String.init)
        guard codes.count == 2, let a = model.airports.search(codes[0], limit: 1).first,
              let b = model.airports.search(codes[1], limit: 1).first else { return }
        model.draft.origin = a.place
        model.draft.destination = b.place
        model.draft.goal = LaunchFlags.value("--demo-goal") ?? "Finish the chapter draft"
        let stage = LaunchFlags.value("--demo-stage") ?? "plan"
        if stage == "plan" { return }
        model.goToBoarding()
        if stage == "boarding" { return }
        if LaunchFlags.has("--demo-desktop") { model.desktopMode = true }
        model.takeOff()
        if stage == "landed" { model.endEarly() }
    }
}
