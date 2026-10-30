import ContrailCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var newCategory = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Settings").font(.system(size: 24, weight: .semibold))
                group("Flight") {
                    HStack {
                        Text("Flying height")
                        Picker("Flying height", selection: $model.settings.cruiseAltitude) {
                            ForEach(CruiseAltitude.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                    Toggle("Show place names, roads and airports on the map", isOn: $model.settings.mapLabels)
                    HStack {
                        Text("Motion")
                        Picker("Motion", selection: $model.settings.smoothMotion) {
                            Text("Smooth · uses more energy").tag(true)
                            Text("Energy saver · small steps").tag(false)
                        }
                        .labelsHidden().fixedSize()
                    }
                    Toggle("Landing chime", isOn: $model.settings.chimeOn)
                    Toggle("Crash animation when a flight is ended early", isOn: $model.settings.crashAnimation)
                    Toggle("Keep the display awake during flights", isOn: $model.settings.keepAwake)
                    Toggle("Start flights in desktop mode", isOn: Binding(get: { model.settings.desktopModeByDefault }, set: {
                        model.settings.desktopModeByDefault = $0
                        if model.stage != .flying { model.desktopMode = $0 }
                    }))
                    Toggle(isOn: $model.settings.wallpaperSync) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sync wallpaper to the route")
                            Text("Sets your wallpaper to a still image of the route during a flight, then restores yours. Off by default.")
                                .font(.system(size: 11)).foregroundStyle(Theme.dim)
                        }
                    }
                    HStack {
                        Text("Distance units")
                        Picker("Distance units", selection: $model.settings.units) {
                            Text("Kilometres").tag(DistanceUnit.km)
                            Text("Miles").tag(DistanceUnit.mi)
                        }
                        .labelsHidden().fixedSize()
                    }
                    HStack {
                        Text("Hide flight controls after")
                        Slider(value: $model.settings.hudHideSeconds, in: 2...20, step: 1).frame(width: 160)
                        Text("\(Int(model.settings.hudHideSeconds)) s").font(.system(size: 12, design: .monospaced))
                    }
                }
                group("Categories") {
                    ForEach($model.categories) { $c in
                        HStack(spacing: 10) {
                            ColorPicker("", selection: Binding(get: { Color(hex: c.colorHex) }, set: { c.colorHex = $0.hexString }), supportsOpacity: false)
                                .labelsHidden().frame(width: 40)
                            TextField("Name", text: $c.name).textFieldStyle(.roundedBorder).frame(width: 200)
                            Toggle("Archived", isOn: $c.archived).toggleStyle(.checkbox)
                            Spacer()
                        }
                        .opacity(c.archived ? 0.55 : 1)
                    }
                    HStack {
                        TextField("New category", text: $newCategory).textFieldStyle(.roundedBorder).frame(width: 200)
                            .onSubmit(addCategory)
                        Button("Add", action: addCategory).disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("Archived categories keep their history in the logbook.").font(.system(size: 11)).foregroundStyle(Theme.faint)
                }
                group("Your music") {
                    Toggle("Shuffle", isOn: $model.settings.mix.shuffleLibrary)
                    if model.library.isEmpty {
                        Text("Add MP3, M4A, AAC, WAV or AIFF files. They stay where they are on disk.").font(.system(size: 12)).foregroundStyle(Theme.dim)
                    }
                    ForEach(model.library) { t in
                        HStack {
                            Image(systemName: FileManager.default.fileExists(atPath: t.path) ? "music.note" : "exclamationmark.triangle")
                                .foregroundStyle(Theme.dim)
                            Text(t.title).lineLimit(1)
                            Spacer()
                            Button { model.library.removeAll { $0.id == t.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain).accessibilityLabel("Remove \(t.title)")
                        }
                        .font(.system(size: 12))
                    }
                    HStack {
                        Button("Add files…") { addMusic(folders: false) }
                        Button("Add folder…") { addMusic(folders: true) }
                        if !model.library.isEmpty { Button("Remove all") { model.library = [] } }
                    }
                }
                group("About") {
                    Text("Satellite imagery and place search by Apple Maps. Airport names and codes from OurAirports (public domain). Sounds are synthesised by Focus on Flight.")
                        .font(.system(size: 12)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                    Text("Data folder: \(model.store.dir.path)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.faint)
                        .textSelection(.enabled)
                }
            }
            .padding(26)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: 720)
        .glassPanel(radius: 28)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title)
            VStack(alignment: .leading, spacing: 10) { content() }
                .font(.system(size: 13))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.04)))
        }
    }

    private func addCategory() {
        let name = newCategory.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let palette = ["#6FA8DC", "#93C47D", "#E6B85C", "#C27BA0", "#76A5AF", "#E06666", "#8E7CC3", "#F6B26B"]
        model.categories.append(FocusCategory(name: name, colorHex: palette[model.categories.count % palette.count]))
        newCategory = ""
    }

    private func addMusic(folders: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !folders
        panel.canChooseDirectories = folders
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK else { return }
        let exts: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff"]
        var found: [URL] = []
        for url in panel.urls {
            if folders, let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                for case let f as URL in e where exts.contains(f.pathExtension.lowercased()) { found.append(f) }
            } else if exts.contains(url.pathExtension.lowercased()) {
                found.append(url)
            }
        }
        let existing = Set(model.library.map(\.path))
        let added = found.filter { !existing.contains($0.path) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { MusicTrack(path: $0.path, title: $0.deletingPathExtension().lastPathComponent) }
        model.library += added
        if added.isEmpty { model.show("No new audio files found.") }
    }
}
