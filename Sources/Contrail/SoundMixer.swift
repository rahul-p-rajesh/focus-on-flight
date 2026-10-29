import AVFoundation
import Foundation
import Observation

struct SoundLayer: Identifiable, Hashable {
    enum Group { case ambience, music }
    let id: String
    let title: String
    let symbol: String
    let group: Group
}

/// Plays the ambience layers and one music source, with smooth fades.
@Observable @MainActor final class SoundMixer {
    static let ambience: [SoundLayer] = [
        SoundLayer(id: "cabin", title: "Cabin", symbol: "airplane", group: .ambience),
        SoundLayer(id: "rain_shelter", title: "Rain on Roof", symbol: "cloud.rain", group: .ambience),
        SoundLayer(id: "heavy_rain", title: "Downpour", symbol: "cloud.heavyrain", group: .ambience),
        SoundLayer(id: "raindrop", title: "Dripping Eaves", symbol: "drop", group: .ambience),
        SoundLayer(id: "thunderstorm", title: "Distant Storm", symbol: "cloud.bolt.rain", group: .ambience),
        SoundLayer(id: "waterfall", title: "Waterfall", symbol: "water.waves", group: .ambience),
        SoundLayer(id: "forest", title: "Forest", symbol: "tree", group: .ambience),
        SoundLayer(id: "ocean", title: "Ocean", symbol: "beach.umbrella", group: .ambience),
        SoundLayer(id: "blizzard", title: "Snow Wind", symbol: "wind.snow", group: .ambience),
    ]
    static let music: [SoundLayer] = [
        SoundLayer(id: "music_drift", title: "Drift", symbol: "sun.horizon", group: .music),
        SoundLayer(id: "music_anchor", title: "Anchor", symbol: "circle.dotted.circle", group: .music),
        SoundLayer(id: "music_current", title: "Current", symbol: "waveform", group: .music),
    ]

    var mix: SoundMix { didSet { if mix != oldValue { onMixChange?(mix); update() } } }
    var library: [MusicTrack] = [] { didSet { if mix.music == "library" { rebuildLibraryQueue() } } }
    /// 0 before takeoff and after landing, 1 in flight. Faded, not switched.
    private(set) var flightGain = 0.0
    var ducked = false { didSet { if ducked != oldValue { update() } } }
    /// True while the sound panel is open outside a flight, so changes can be heard.
    var previewing = false { didSet { if previewing != oldValue { update() } } }
    var onMixChange: ((SoundMix) -> Void)?

    private struct Channel { let player: AVQueuePlayer; let looper: AVPlayerLooper? }
    private var channels: [String: Channel] = [:]
    private var libraryPlayer: AVQueuePlayer?
    private var libraryEndObserver: NSObjectProtocol?
    private var chimePlayer: AVAudioPlayer?
    private var rampTimer: Timer?
    private var gainTarget = 0.0

    init(mix: SoundMix) { self.mix = mix }

    // MARK: Public controls

    func toggle(_ layer: SoundLayer) {
        switch layer.group {
        case .ambience:
            if mix.active.contains(layer.id) { mix.active.remove(layer.id) } else { mix.active.insert(layer.id) }
        case .music:
            mix.music = mix.music == layer.id ? nil : layer.id
        }
    }

    func toggleLibrary() { mix.music = mix.music == "library" ? nil : "library" }

    func setVolume(_ id: String, _ v: Double) {
        if id == "music" { mix.musicVolume = v } else { mix.volumes[id] = v }
    }

    func isOn(_ layer: SoundLayer) -> Bool {
        layer.group == .ambience ? mix.active.contains(layer.id) : mix.music == layer.id
    }

    /// Fade all flight audio in (takeoff) or out (landing).
    func setFlightActive(_ on: Bool, fade: Double = 3) {
        gainTarget = on ? 1 : 0
        rampSeconds = fade
        update()
    }

    func playChime() {
        guard let url = AppResources.url("chime", "m4a", in: "Sounds") else { return }
        chimePlayer = try? AVAudioPlayer(contentsOf: url)
        chimePlayer?.volume = 0.8
        chimePlayer?.play()
    }

    func stopAll() {
        for (_, c) in channels { c.player.pause() }
        channels.removeAll()
        libraryPlayer?.pause()
        libraryPlayer = nil
    }

    /// For tests: each live player's id, volume and whether it is playing.
    var debugState: String {
        var parts = channels.map { "\($0.key)=\(String(format: "%.2f", $0.value.player.volume))/\($0.value.player.rate > 0 ? "playing" : "stopped")" }
        if let lp = libraryPlayer { parts.append("library=\(String(format: "%.2f", lp.volume))") }
        return "gain=\(String(format: "%.2f", flightGain)) " + parts.sorted().joined(separator: ",")
    }

    // MARK: Engine

    private var rampSeconds = 1.0

    private var effectiveGain: Double { max(flightGain, previewing ? 1 : 0) }

    private func target(for id: String) -> Float {
        guard mix.masterOn else { return 0 }
        let isMusic = id.hasPrefix("music_") || id == "library"
        let on = isMusic ? mix.music == id : mix.active.contains(id)
        guard on else { return 0 }
        let base = isMusic ? mix.musicVolume : mix.volume(id)
        return Float(base * effectiveGain * (isMusic && ducked ? 0.3 : 1))
    }

    private func update() {
        if rampTimer == nil { rampSeconds = max(rampSeconds, 0.8) }
        // Create players for anything that should now be audible.
        let wanted = Set(mix.active).union(mix.music.map { [$0] } ?? [])
        let audible = mix.masterOn && max(gainTarget, previewing ? 1 : 0) > 0
        for id in wanted where audible {
            if id == "library" { ensureLibrary() } else { ensureChannel(id) }
        }
        startRamp()
    }

    private func ensureChannel(_ id: String) {
        guard channels[id] == nil, let url = AppResources.url(id, "m4a", in: "Sounds") else { return }
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.volume = 0
        let looper = AVPlayerLooper(player: player, templateItem: item)
        player.play()
        channels[id] = Channel(player: player, looper: looper)
    }

    private func ensureLibrary() {
        if libraryPlayer == nil { rebuildLibraryQueue() }
    }

    private func rebuildLibraryQueue() {
        let wasVolume = libraryPlayer?.volume ?? 0
        libraryPlayer?.pause()
        if let o = libraryEndObserver { NotificationCenter.default.removeObserver(o) }
        libraryEndObserver = nil
        libraryPlayer = nil
        guard mix.music == "library", !library.isEmpty else { return }
        let tracks = mix.shuffleLibrary ? library.shuffled() : library
        let items = tracks.map { AVPlayerItem(url: URL(fileURLWithPath: $0.path)) }
        let p = AVQueuePlayer(items: items)
        p.volume = wasVolume
        p.actionAtItemEnd = .advance
        if let last = items.last {
            libraryEndObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: last, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuildLibraryQueue() } // repeat the playlist
            }
        }
        p.play()
        libraryPlayer = p
    }

    private func startRamp() {
        guard rampTimer == nil else { return }
        rampTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    private func step() {
        let dt = 1.0 / 30
        let gStep = dt / max(rampSeconds, 0.1)
        if flightGain < gainTarget { flightGain = min(gainTarget, flightGain + gStep) }
        else if flightGain > gainTarget { flightGain = max(gainTarget, flightGain - gStep) }

        var busy = flightGain != gainTarget
        let vStep = Float(dt / 1.0)
        func approach(_ player: AVQueuePlayer, _ t: Float) -> Bool {
            let v = player.volume
            if abs(v - t) <= vStep { player.volume = t } else { player.volume = v + (t > v ? vStep : -vStep) }
            if t > 0, player.rate == 0 { player.play() }
            return player.volume != t
        }
        for (id, c) in channels {
            let t = target(for: id)
            if approach(c.player, t) { busy = true }
            else if t == 0 { c.player.pause(); channels[id] = nil } // silent: release it
        }
        if let lp = libraryPlayer {
            let t = target(for: "library")
            if approach(lp, t) { busy = true } else if t == 0 { lp.pause() }
        }
        if !busy {
            rampTimer?.invalidate()
            rampTimer = nil
            rampSeconds = 1
        }
    }
}
