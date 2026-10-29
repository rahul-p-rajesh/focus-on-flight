import SwiftUI

/// Opens the sound panel. Each button owns its popover; the primary one also answers menu requests.
struct SoundButton: View {
    @Bindable var model: AppModel
    var isPrimary = false
    @State private var presented = false

    var body: some View {
        GlassIconButton(symbol: model.settings.mix.masterOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                        label: "Sound", active: presented) {
            presented.toggle()
        }
        .popover(isPresented: $presented, arrowEdge: .top) {
            SoundPanel(model: model)
        }
        .onChange(of: presented) { model.showSoundPanel = presented }
        .onChange(of: model.soundPanelRequest) { if isPrimary { presented.toggle() } }
        .onDisappear { if presented { presented = false; model.showSoundPanel = false } }
    }
}

/// Our sound mixer: one master switch, ambience layers that mix, one music source.
struct SoundPanel: View {
    @Bindable var model: AppModel
    private var sound: SoundMixer { model.sound }
    private let cols = [GridItem(.adaptive(minimum: 128, maximum: 160), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Sound").font(.system(size: 17, weight: .semibold))
                Spacer()
                Toggle(isOn: Binding(get: { model.settings.mix.masterOn }, set: { sound.mix.masterOn = $0 })) {
                    Text(model.settings.mix.masterOn ? "On" : "Off").font(.system(size: 12, weight: .medium))
                }
                .toggleStyle(.switch).controlSize(.small)
                .accessibilityLabel("All sound")
            }
            SectionLabel("Ambience · mix any")
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(SoundMixer.ambience) { layer in tile(layer) }
            }
            SectionLabel("Focus music · one at a time")
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(SoundMixer.music) { layer in tile(layer) }
                libraryTile
            }
            if model.library.isEmpty {
                Text("To play your own music, add files in Settings → Your music.").font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            if model.stage != .flying {
                Text("Sounds play while the panel is open so you can try them. In flight they fade in after takeoff.")
                    .font(.system(size: 11)).foregroundStyle(Theme.faint).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(width: 520)
        .opacity(model.settings.mix.masterOn ? 1 : 0.55)
    }

    private func tile(_ layer: SoundLayer) -> some View {
        let on = sound.isOn(layer)
        let volID = layer.group == .music ? "music" : layer.id
        let vol = layer.group == .music ? model.settings.mix.musicVolume : model.settings.mix.volume(layer.id)
        return SoundTile(title: layer.title, symbol: layer.symbol, on: on, volume: vol,
                         toggle: { sound.toggle(layer) }, setVolume: { sound.setVolume(volID, $0) })
    }

    private var libraryTile: some View {
        let on = model.settings.mix.music == "library"
        return SoundTile(title: model.library.isEmpty ? "Your music" : "Your music · \(model.library.count)",
                         symbol: "music.note.list", on: on, volume: model.settings.mix.musicVolume,
                         toggle: { if !model.library.isEmpty { sound.toggleLibrary() } },
                         setVolume: { sound.setVolume("music", $0) })
            .opacity(model.library.isEmpty ? 0.5 : 1)
    }
}

struct SoundTile: View {
    let title: String
    let symbol: String
    let on: Bool
    let volume: Double
    let toggle: () -> Void
    let setVolume: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: symbol).font(.system(size: 16)).frame(width: 22, height: 20, alignment: .leading)
                        Spacer()
                        Circle().fill(on ? Theme.accent : .white.opacity(0.2)).frame(width: 7, height: 7)
                    }
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(on ? "on" : "off")")
            Slider(value: Binding(get: { volume }, set: setVolume), in: 0...1)
                .controlSize(.mini)
                .disabled(!on)
                .opacity(on ? 1 : 0.3)
                .accessibilityLabel("\(title) volume")
        }
        .padding(11)
        .frame(minHeight: 92)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? Theme.accent.opacity(0.2) : .white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Theme.accent.opacity(0.55) : .white.opacity(0.08)))
        .animation(.easeOut(duration: 0.2), value: on)
    }
}
