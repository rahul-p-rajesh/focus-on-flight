import ContrailCore
import MapKit
import SwiftUI

/// Globe behind the planning screens. Shows town names, airports, the route, the reachable ring and suggestions.
/// Click any airport or town on the map to depart from it or fly to it.
struct PlanningMap: View {
    @Bindable var model: AppModel
    @State private var position: MapCameraPosition = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 25, longitude: 10),
                                                                       distance: 24_000_000, heading: 0, pitch: 0))
    @State private var region: MKCoordinateRegion?
    @State private var picked: PickedPlace?
    private var draft: FlightDraft { model.draft }

    /// A spot clicked on the map, or one of the airport markers.
    struct PickedPlace: Equatable {
        let coordinate: Coordinate
        let airport: Airport?
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                ForEach(visibleAirports, id: \.code) { a in
                    Annotation("", coordinate: a.coordinate.cl) {
                        Button { picked = PickedPlace(coordinate: a.coordinate, airport: a) } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "airplane").font(.system(size: 8, weight: .bold))
                                Text(a.code).font(.system(size: 10, weight: .bold, design: .monospaced))
                            }
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(.black.opacity(a.size == 2 ? 0.62 : 0.45)))
                            .foregroundStyle(.white.opacity(a.size == 2 ? 1 : 0.85))
                        }
                        .buttonStyle(.plain)
                        .help(a.name)
                    }
                    .annotationTitles(.hidden)
                }
                if let o = draft.origin {
                    Annotation("", coordinate: o.coordinate.cl) { PlacePin(place: o, isOrigin: true) }.annotationTitles(.hidden)
                    if draft.mode == .time {
                        MapCircle(center: o.coordinate.cl, radius: FlightTiming.distanceKm(forMinutes: draft.minutes) * 1000)
                            .foregroundStyle(Theme.accent.opacity(0.06))
                            .stroke(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                        ForEach(draft.suggestions) { c in
                            Annotation("", coordinate: c.place.coordinate.cl) {
                                Button { model.draft.destination = c.place } label: {
                                    Text(c.place.code).font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(Capsule().fill(draft.destination == c.place ? Theme.accent : .black.opacity(0.6)))
                                        .foregroundStyle(draft.destination == c.place ? .black : .white)
                                }
                                .buttonStyle(.plain)
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                }
                if let o = draft.origin, let d = draft.destination {
                    MapPolyline(coordinates: Geo.path(o.coordinate, d.coordinate, segments: 96).map(\.cl))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 6]))
                    Annotation("", coordinate: d.coordinate.cl) { PlacePin(place: d, isOrigin: false) }.annotationTitles(.hidden)
                }
            }
            .mapStyle(.hybrid(elevation: .realistic, pointsOfInterest: .including([.airport]), showsTraffic: false))
            .mapControls { MapZoomStepper(); MapCompass() }
            .safeAreaPadding(.leading, model.tab == .fly && model.stage == .planning ? 430 : 0)
            .safeAreaPadding(.top, 60)
            .onMapCameraChange(frequency: .onEnd) { region = $0.region }
            .onTapGesture { pt in
                guard let c = proxy.convert(pt, from: .local) else { return }
                if let target = draft.picking {
                    Task { await model.pick(Coordinate(c), for: target) }
                } else if model.tab == .fly && model.stage == .planning {
                    picked = PickedPlace(coordinate: Coordinate(c), airport: nil)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if model.tab == .fly && model.stage == .planning, let p = picked {
                PickCard(picked: p, model: model) { picked = nil }
                    .id(p.coordinate)
                    .padding(.trailing, 24).padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: picked)
        .ignoresSafeArea()
        .onChange(of: cameraKey) { fit() }
        .onAppear { fit(animated: false) }
    }

    /// Bundled airports in view: big ones when zoomed out, medium ones too when closer.
    /// Very close in, Apple's own airport icons take over.
    private var visibleAirports: [Airport] {
        guard model.tab == .fly, model.stage == .planning, let r = region else { return [] }
        let span = r.span.latitudeDelta
        guard span < 45, span > 0.8 else { return [] }
        let minSize = span > 12 ? 2 : 1
        let lonHalf = min(180, r.span.longitudeDelta / 2)
        let minLon = Geo.normalizedLongitude(r.center.longitude - lonHalf)
        let maxLon = Geo.normalizedLongitude(r.center.longitude + lonHalf)
        let skip = Set([draft.origin?.code, draft.destination?.code].compactMap { $0 })
        return model.airports.inBox(minLat: r.center.latitude - span / 2, maxLat: r.center.latitude + span / 2,
                                    minLon: minLon, maxLon: maxLon, minSize: minSize, limit: 70)
            .filter { !skip.contains($0.code) }
    }

    private var cameraKey: String {
        "\(draft.origin?.id ?? "-")|\(draft.destination?.id ?? "-")|\(draft.mode.rawValue)|\(Int(draft.minutes))"
    }

    private func fit(animated: Bool = true) {
        var cam: MapCamera?
        if let o = draft.origin, let d = draft.destination {
            let km = Geo.distanceKm(o.coordinate, d.coordinate)
            let mid = Geo.interpolate(o.coordinate, d.coordinate, fraction: 0.5)
            cam = MapCamera(centerCoordinate: mid.cl, distance: min(24_000_000, max(500_000, km * 1000 * 2.8)), heading: 0, pitch: 0)
        } else if let o = draft.origin {
            let ring = draft.mode == .time ? FlightTiming.distanceKm(forMinutes: draft.minutes) : 600
            cam = MapCamera(centerCoordinate: o.coordinate.cl, distance: min(24_000_000, max(900_000, ring * 1000 * 5)), heading: 0, pitch: 0)
        }
        guard let cam else { return }
        if animated { withAnimation(.easeInOut(duration: 1.4)) { position = .camera(cam) } } else { position = .camera(cam) }
    }
}

/// Small card for a place clicked on the map: the nearest real airport within 30 km, otherwise a made-up airfield.
struct PickCard: View {
    let picked: PlanningMap.PickedPlace
    @Bindable var model: AppModel
    let close: () -> Void
    @State private var place: Place?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "airplane.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.accent)
                if let p = place {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(p.code).font(.system(size: 13, weight: .bold, design: .monospaced))
                            Text(p.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                            if p.isMadeUp { MadeUpMark() }
                        }
                        if let l = p.locality { Text(l).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1) }
                    }
                } else {
                    Text("Finding the nearest airfield…").font(.system(size: 13)).foregroundStyle(Theme.dim)
                    ProgressView().controlSize(.small)
                }
                Spacer(minLength: 0)
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                    .buttonStyle(.plain).accessibilityLabel("Close")
            }
            HStack(spacing: 8) {
                Button("Depart from here") { use(.origin) }.buttonStyle(SecondaryButtonStyle())
                if model.draft.mode == .route {
                    Button("Fly here") { use(.destination) }.buttonStyle(PrimaryButtonStyle())
                }
            }
            .disabled(place == nil)
        }
        .padding(16)
        .frame(width: 340)
        .glassPanel(radius: 20)
        .task {
            if let a = picked.airport { place = a.place } else { place = await model.places.resolve(picked.coordinate) }
        }
    }

    private func use(_ target: PickTarget) {
        guard let p = place else { return }
        model.setPlace(p, for: target)
        close()
    }
}

struct PlacePin: View {
    let place: Place
    let isOrigin: Bool
    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Text(place.code).font(.system(size: 11, weight: .bold, design: .monospaced))
                if place.isMadeUp { MadeUpMark() }
            }
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(.black.opacity(0.65)))
            Circle().fill(isOrigin ? .white : Theme.accent).frame(width: 9, height: 9)
                .overlay(Circle().stroke(.black.opacity(0.5), lineWidth: 1))
        }
    }
}

/// Left-hand planning panel.
struct PlanPanel: View {
    @Bindable var model: AppModel
    @Bindable var draft: FlightDraft

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.scrollIndicators(.never)
        }
        .frame(width: 400)
        .glassPanel(radius: 26)
        .onChange(of: draft.mode) {
            if draft.mode == .time { draft.destination = nil; model.refreshSuggestions() }
        }
    }

    private var content: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Plan a flight").font(.system(size: 22, weight: .semibold))
                Picker("Plan", selection: $draft.mode) {
                    ForEach(PlanMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()

                PlaceField(label: "From", target: .origin, model: model)
                if draft.mode == .route {
                    PlaceField(label: "To", target: .destination, model: model)
                } else {
                    durationPicker
                }
                routeSummary
                categoryPicker
                goalField
                HStack {
                    Spacer()
                    Button("Continue to boarding") { model.goToBoarding() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!model.canContinue)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(22)
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Study time")
                Spacer()
                Text(TimeFormat.duration(minutes: draft.minutes)).font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
            Slider(value: $draft.minutes, in: 15...240, step: 5) {
                Text("Study time")
            } onEditingChanged: { editing in
                if !editing { model.refreshSuggestions() }
            }
            .labelsHidden()
            .onChange(of: draft.minutes) { model.refreshSuggestions() }

            if draft.origin == nil {
                Text("Choose where you leave from. We'll suggest places about this far away by air.")
                    .font(.system(size: 12)).foregroundStyle(Theme.dim)
            } else {
                HStack {
                    SectionLabel("Destinations")
                    if draft.suggestionsLoading { ProgressView().controlSize(.small) }
                    Spacer()
                    Button { model.refreshSuggestions(shuffle: true) } label: { Label("Shuffle", systemImage: "shuffle") }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(draft.suggestionsLoading)
                }
                if draft.suggestionsWidened {
                    Text("Few places match this time exactly, so the range was widened.").font(.system(size: 11)).foregroundStyle(Theme.dim)
                }
                if !draft.suggestionsLoading && draft.suggestions.isEmpty {
                    Text("No land destinations found. Try another time or departure.").font(.system(size: 12)).foregroundStyle(Theme.dim)
                }
                VStack(spacing: 4) {
                    ForEach(draft.suggestions) { c in
                        Button { draft.destination = c.place } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "location.north.fill").font(.system(size: 10))
                                    .rotationEffect(.degrees(c.bearing)).foregroundStyle(Theme.dim)
                                    .accessibilityHidden(true)
                                Text(c.place.code).font(.system(size: 12, weight: .bold, design: .monospaced))
                                Text(c.place.name).font(.system(size: 12)).lineLimit(1)
                                if c.place.isMadeUp { MadeUpMark() }
                                Spacer()
                                Text(TimeFormat.duration(minutes: c.minutes)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.dim)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 9).fill(draft.destination == c.place ? Theme.accent.opacity(0.22) : .white.opacity(0.04)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private var routeSummary: some View {
        if let km = model.draftDistanceKm, let routeMinutes = model.draftMinutes {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(model.settings.units.format(km))
                    Text("·").foregroundStyle(Theme.faint)
                    Text("\(TimeFormat.duration(minutes: routeMinutes)) by air").foregroundStyle(Theme.dim)
                }
                .font(.system(size: 13))
                if model.routeProblem == nil, let study = model.effectiveStudyMinutes, let journey = model.journeyMinutes {
                    HStack {
                        SectionLabel("Study time")
                        Spacer()
                        Text(TimeFormat.duration(minutes: study)).font(.system(size: 15, weight: .semibold, design: .monospaced))
                    }
                    if draft.mode == .route {
                        Slider(value: Binding(get: { study }, set: { draft.studyMinutes = $0 }), in: 15...480, step: 5)
                            .labelsHidden()
                            .accessibilityLabel("Study time")
                        HStack(alignment: .firstTextBaseline) {
                            Text(draft.studyMinutes == nil ? "Set from the flight time. Drag to choose your own."
                                                           : "Your plane flies this route in exactly this time.")
                                .foregroundStyle(Theme.dim)
                            Spacer()
                            if draft.studyMinutes != nil {
                                Button("Use flight time") { draft.studyMinutes = nil }
                                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                            }
                        }
                        .font(.system(size: 11))
                    }
                    let p = model.settings.pomodoro
                    let total = journey * 60
                    if p.enabled {
                        PomodoroBar(segments: p.segments(total: total), elapsed: 0, total: total, height: 6)
                        let breaks = p.breakCount(total: total)
                        Text("\(breaks) break\(breaks == 1 ? "" : "s") of \(Int(p.breakMinutes)) min · journey \(TimeFormat.duration(minutes: journey))")
                            .font(.system(size: 12)).foregroundStyle(Theme.dim)
                    } else {
                        Text("One focus block · journey \(TimeFormat.duration(minutes: journey))")
                            .font(.system(size: 12)).foregroundStyle(Theme.dim)
                    }
                }
                if let problem = model.routeProblem { Text(problem).font(.system(size: 12)).foregroundStyle(.orange) }
                if let w = model.routeWarning { Text(w).font(.system(size: 12)).foregroundStyle(.yellow.opacity(0.9)) }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Category")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(model.activeCategories) { c in
                    Button { draft.categoryID = c.id } label: {
                        HStack(spacing: 6) {
                            Circle().fill(Color(hex: c.colorHex)).frame(width: 8, height: 8)
                            Text(c.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(draft.categoryID == c.id ? Color(hex: c.colorHex).opacity(0.3) : .white.opacity(0.06)))
                        .overlay(Capsule().strokeBorder(draft.categoryID == c.id ? Color(hex: c.colorHex) : .clear))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(draft.categoryID == c.id ? .isSelected : [])
                }
            }
        }
    }

    private var goalField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("Goal")
                Spacer()
                Text("\(draft.goal.count)/140").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.faint)
            }
            TextField("What will you finish on this flight?", text: $draft.goal, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...3)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
                .onChange(of: draft.goal) { if draft.goal.count > 140 { draft.goal = String(draft.goal.prefix(140)) } }
        }
    }
}

/// Search field for a departure or arrival: places, addresses and airports, plus "Near me" and "Pick on globe".
struct PlaceField: View {
    let label: String
    let target: PickTarget
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var results: [PlaceResult] = []
    @State private var editing = false
    @State private var searching = false
    @State private var locating = false
    @State private var note: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var place: Place? { target == .origin ? model.draft.origin : model.draft.destination }
    private var picking: Bool { model.draft.picking == target }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(label)
            HStack(spacing: 8) {
                if let p = place, !editing {
                    Button { editing = true; query = ""; focused = true } label: {
                        HStack(spacing: 8) {
                            Text(p.code).font(.system(size: 17, weight: .bold, design: .monospaced))
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(p.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    if p.isMadeUp { MadeUpMark() }
                                }
                                if let l = p.locality { Text(l).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1) }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Change")
                } else {
                    TextField("City, address or airport", text: $query)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onSubmit { if let r = results.first { Task { await choose(r) } } }
                        .onChange(of: query) { search() }
                        .onExitCommand { editing = false; query = "" }
                    if searching { ProgressView().controlSize(.mini) }
                }
                Button {
                    Task { await nearMe() }
                } label: {
                    if locating { ProgressView().controlSize(.mini) } else { Image(systemName: "location") }
                }
                .buttonStyle(.plain).help("Near me").accessibilityLabel("Use my location")
                Button {
                    model.draft.picking = picking ? nil : target
                } label: {
                    Image(systemName: picking ? "mappin.circle.fill" : "mappin.and.ellipse")
                        .foregroundStyle(picking ? Theme.accent : .white)
                }
                .buttonStyle(.plain).help("Pick a point on the globe").accessibilityLabel("Pick on the globe")
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(picking ? 0.1 : 0.06)))

            if editing || place == nil, !results.isEmpty {
                VStack(spacing: 2) {
                    ForEach(results) { r in
                        Button { Task { await choose(r) } } label: {
                            HStack(spacing: 8) {
                                Image(systemName: r.kind == .airport ? "airplane.departure" : "mappin").font(.system(size: 11))
                                    .foregroundStyle(Theme.dim).frame(width: 14)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    if !r.subtitle.isEmpty { Text(r.subtitle).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1) }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.35)))
            }
            if picking {
                Text("Click anywhere on the globe. You can pan and zoom first.").font(.system(size: 11)).foregroundStyle(Theme.accent)
            }
            if let note { Text(note).font(.system(size: 11)).foregroundStyle(.orange) }
        }
        .onChange(of: place) { editing = false; query = ""; results = [] }
    }

    private func search() {
        searchTask?.cancel()
        note = nil
        let q = query
        let airports = model.places.searchAirports(q)
        results = airports
        guard q.trimmingCharacters(in: .whitespaces).count >= 2 else { searching = false; return }
        searching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let places = await model.places.searchPlaces(q)
            guard !Task.isCancelled else { return }
            results = Array((airports + places).prefix(9))
            searching = false
        }
    }

    private func choose(_ r: PlaceResult) async {
        searchTask?.cancel()
        searching = false
        await model.choose(r, for: target)
        editing = false
        results = []
        query = ""
    }

    private func nearMe() async {
        locating = true
        note = nil
        let ok = await model.useCurrentLocation(for: target)
        locating = false
        if !ok { note = "Your location is unavailable. Type a city instead." }
    }
}
