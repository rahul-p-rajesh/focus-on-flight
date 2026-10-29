import SwiftUI

enum Theme {
    static let accent = Color(red: 0.55, green: 0.78, blue: 1.0)
    static let tint = Color(red: 0.04, green: 0.07, blue: 0.06).opacity(0.38)
    static let dim = Color.white.opacity(0.62)
    static let faint = Color.white.opacity(0.4)
}

/// Tinted Liquid Glass, or a solid panel when Reduce Transparency is on.
struct GlassPanel: ViewModifier {
    var radius: CGFloat = 22
    var tint: Color = Theme.tint
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color(white: 0.11)))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.12)))
        } else {
            content.glassEffect(interactive ? .regular.tint(tint).interactive() : .regular.tint(tint),
                                in: .rect(cornerRadius: radius, style: .continuous))
        }
    }
}

extension View {
    func glassPanel(radius: CGFloat = 22, tint: Color = Theme.tint, interactive: Bool = false) -> some View {
        modifier(GlassPanel(radius: radius, tint: tint, interactive: interactive))
    }
}

/// Round glass icon button used in the flight controls.
struct GlassIconButton: View {
    let symbol: String
    let label: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 38, height: 38)
                .foregroundStyle(active ? Theme.accent : .white)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(active ? Theme.accent.opacity(0.18) : Theme.tint).interactive(), in: .circle)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 18).padding(.vertical, 10)
            .foregroundStyle(enabled ? Color.black : Color.white.opacity(0.4))
            .background(Capsule().fill(enabled ? Theme.accent : Color.white.opacity(0.08)))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(.white)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0.09)))
    }
}

struct SectionLabel: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.faint)
    }
}

/// "Made-up" marker for invented airfields.
struct MadeUpMark: View {
    var body: some View {
        Image(systemName: "sparkle").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.accent.opacity(0.85))
            .help("Made-up airfield name").accessibilityLabel("Made-up name")
    }
}

/// Gives the model a handle on the main window.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Reports whether the hosting window is visible (not minimised, hidden or fully covered).
struct OcclusionReader: NSViewRepresentable {
    let onChange: (Bool) -> Void
    func makeNSView(context: Context) -> ReaderView { let v = ReaderView(); v.onChange = onChange; return v }
    func updateNSView(_ v: ReaderView, context: Context) { v.onChange = onChange }

    final class ReaderView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil }
            guard let w = window else { onChange?(false); return }
            onChange?(w.occlusionState.contains(.visible))
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: w, queue: .main) { [weak self, weak w] _ in
                self?.onChange?(w?.occlusionState.contains(.visible) ?? false)
            }
        }

        deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }
    }
}
