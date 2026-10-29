import SwiftUI
import AppKit
import ContrailCore
import Foundation

/// Finds bundled resources in the .app, or in the repo's Resources folder during development.
enum AppResources {
    static let root: URL? = {
        if let url = Bundle.main.resourceURL, FileManager.default.fileExists(atPath: url.appendingPathComponent("airports.json").path) {
            return url
        }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Resources")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("airports.json").path) { return candidate }
            dir.deleteLastPathComponent()
        }
        return nil
    }()

    static func url(_ name: String, _ ext: String, in sub: String? = nil) -> URL? {
        guard let root else { return nil }
        var u = root
        if let sub { u.appendPathComponent(sub) }
        u.appendPathComponent("\(name).\(ext)")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
}

/// Developer launch flags, used for testing. None are needed in normal use.
enum LaunchFlags {
    static let args = CommandLine.arguments
    static func value(_ name: String) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    static func has(_ name: String) -> Bool { args.contains(name) }
}

/// Small JSON files in Application Support.
@MainActor final class Store {
    let dir: URL

    init() {
        if let custom = LaunchFlags.value("--data-dir") {
            dir = URL(fileURLWithPath: custom)
        } else {
            dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Contrail", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func load<T: Decodable>(_ name: String, default value: @autoclosure () -> T) -> T {
        let url = dir.appendingPathComponent("\(name).json")
        guard let data = try? Data(contentsOf: url) else { return value() }
        do {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            return try d.decode(T.self, from: data)
        } catch {
            // Keep the unreadable file instead of overwriting it.
            let backup = dir.appendingPathComponent("\(name).unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            NSLog("Contrail: could not read \(name).json, kept a copy at \(backup.path): \(error)")
            return value()
        }
    }

    func save<T: Encodable>(_ name: String, _ value: T) {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try e.encode(value).write(to: dir.appendingPathComponent("\(name).json"), options: .atomic)
        } catch {
            NSLog("Contrail: could not save \(name).json: \(error)")
        }
    }
}

struct SoundMix: Codable, Equatable {
    var masterOn = true
    var active: Set<String> = ["cabin"]
    var volumes: [String: Double] = [:]
    /// A bundled music id, "library" for the user's own files, or nil for no music.
    var music: String?
    var musicVolume = 0.45
    var shuffleLibrary = true

    func volume(_ id: String) -> Double { volumes[id] ?? (id == "cabin" ? 0.55 : 0.5) }

    init() {}

    /// Missing keys fall back to defaults, so older or newer settings files still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SoundMix.Defaults()
        masterOn = try c.decodeIfPresent(Bool.self, forKey: .masterOn) ?? d.masterOn
        active = try c.decodeIfPresent(Set<String>.self, forKey: .active) ?? d.active
        volumes = try c.decodeIfPresent([String: Double].self, forKey: .volumes) ?? [:]
        music = try c.decodeIfPresent(String.self, forKey: .music)
        musicVolume = try c.decodeIfPresent(Double.self, forKey: .musicVolume) ?? d.musicVolume
        shuffleLibrary = try c.decodeIfPresent(Bool.self, forKey: .shuffleLibrary) ?? true
    }

    private struct Defaults { let masterOn = true; let active: Set<String> = ["cabin"]; let musicVolume = 0.45 }
}

enum CruiseAltitude: String, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var metres: Double { switch self { case .low: 5_000; case .medium: 9_000; case .high: 14_000 } }
    var title: String { switch self { case .low: "Low · closest, fastest"; case .medium: "Medium"; case .high: "High · widest, calmest" } }
}

struct AppSettings: Codable, Equatable {
    var cruiseAltitude: CruiseAltitude = .medium
    /// Town names, roads and airports drawn over the satellite imagery.
    var mapLabels = true
    /// Glide the camera every frame (smooth, more energy) or step a few times a second (energy saver).
    var smoothMotion = true
    var chimeOn = true
    var keepAwake = true
    var desktopModeByDefault = false
    var wallpaperSync = false
    var units: DistanceUnit = .km
    var hudHideSeconds = 5.0
    var mix = SoundMix()

    init() {}

    /// Missing keys fall back to defaults, so adding a setting never resets the others.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        cruiseAltitude = (try? c.decodeIfPresent(CruiseAltitude.self, forKey: .cruiseAltitude)) ?? d.cruiseAltitude
        mapLabels = try c.decodeIfPresent(Bool.self, forKey: .mapLabels) ?? d.mapLabels
        smoothMotion = try c.decodeIfPresent(Bool.self, forKey: .smoothMotion) ?? d.smoothMotion
        chimeOn = try c.decodeIfPresent(Bool.self, forKey: .chimeOn) ?? d.chimeOn
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? d.keepAwake
        desktopModeByDefault = try c.decodeIfPresent(Bool.self, forKey: .desktopModeByDefault) ?? d.desktopModeByDefault
        wallpaperSync = try c.decodeIfPresent(Bool.self, forKey: .wallpaperSync) ?? d.wallpaperSync
        units = (try? c.decodeIfPresent(DistanceUnit.self, forKey: .units)) ?? d.units
        hudHideSeconds = try c.decodeIfPresent(Double.self, forKey: .hudHideSeconds) ?? d.hudHideSeconds
        mix = try c.decodeIfPresent(SoundMix.self, forKey: .mix) ?? d.mix
    }
}

struct MusicTrack: Codable, Hashable, Identifiable {
    var path: String
    var title: String
    var id: String { path }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0x888888
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

