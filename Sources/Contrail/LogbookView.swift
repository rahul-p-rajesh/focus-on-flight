import Charts
import ContrailCore
import MapKit
import SwiftUI
import UniformTypeIdentifiers

struct LogbookView: View {
    @Bindable var model: AppModel
    enum Range: String, CaseIterable, Identifiable { case day = "Day", week = "Week", month = "Month"; var id: String { rawValue } }
    @State private var range: Range = .week
    @State private var day = Date()
    @State private var editing: FlightRecord?
    @State private var deleting: FlightRecord?

    private var cal: Calendar { .current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Logbook").font(.system(size: 24, weight: .semibold))
                    Spacer()
                    Button { exportCSV() } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.records.isEmpty)
                }
                totals
                Picker("Range", selection: $range) { ForEach(Range.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                if range == .day { dayView } else { chart }
                routesMap
                entries
            }
            .padding(26)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: 920)
        .glassPanel(radius: 28)
        .sheet(item: $editing) { rec in GoalEditor(record: rec, model: model) }
        .confirmationDialog("Delete this flight from the logbook?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { rec in
            Button("Delete", role: .destructive) { model.records.removeAll { $0.id == rec.id } }
        }
    }

    private var totals: some View {
        let t = Logbook.totals(model.records)
        return HStack(spacing: 12) {
            tile("Time flown", String(format: "%.1f h", t.focusHours))
            tile("Flights", "\(t.flights)")
            tile("Distance", model.settings.units.format(t.distanceKm))
            tile("Places", "\(t.placesVisited)")
        }
    }

    private func tile(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(k)
            Text(v).font(.system(size: 20, weight: .light, design: .monospaced))
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
    }

    private var dayView: some View {
        let s = Logbook.summary(for: day, records: model.records, calendar: cal)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { day = cal.date(byAdding: .day, value: -1, to: day)! } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).accessibilityLabel("Previous day")
                Text(day.formatted(date: .complete, time: .omitted)).font(.system(size: 14, weight: .medium)).frame(minWidth: 220)
                Button { day = cal.date(byAdding: .day, value: 1, to: day)! } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain).accessibilityLabel("Next day")
                    .disabled(cal.isDateInToday(day))
                Spacer()
                Text("\(s.totalSessions) sessions · \(TimeFormat.duration(minutes: s.totalMinutes))").font(.system(size: 13)).foregroundStyle(Theme.dim)
            }
            if s.stats.isEmpty {
                Text("No flights on this day.").font(.system(size: 13)).foregroundStyle(Theme.dim).padding(.vertical, 18)
            }
            ForEach(s.stats, id: \.categoryID) { st in
                let c = model.category(st.categoryID)
                HStack {
                    Circle().fill(Color(hex: c?.colorHex ?? "#888")).frame(width: 10, height: 10)
                    Text(c?.name ?? "Deleted category").font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text("\(st.sessions) session\(st.sessions == 1 ? "" : "s")").font(.system(size: 13)).foregroundStyle(Theme.dim)
                    Text(TimeFormat.duration(minutes: st.focusMinutes)).font(.system(size: 13, design: .monospaced)).frame(width: 80, alignment: .trailing)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.04)))
            }
        }
    }

    private struct Bar: Identifiable { let id = UUID(); let day: Date; let category: String; let minutes: Double }

    private var chart: some View {
        let days = range == .week ? 7 : 30
        let from = cal.date(byAdding: .day, value: -(days - 1), to: Date())!
        let sums = Logbook.daySummaries(records: model.records, from: from, to: Date(), calendar: cal)
        let bars = sums.flatMap { s in s.stats.map { Bar(day: s.day, category: model.category($0.categoryID)?.name ?? "Other", minutes: $0.focusMinutes) } }
        let cats = model.categories
        return VStack(alignment: .leading, spacing: 8) {
            Text("Minutes per day").font(.system(size: 13)).foregroundStyle(Theme.dim)
            Chart(bars) { b in
                BarMark(x: .value("Day", b.day, unit: .day), y: .value("Minutes", b.minutes))
                    .foregroundStyle(by: .value("Category", b.category))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(domain: cats.map(\.name) + ["Other"], range: cats.map { Color(hex: $0.colorHex) } + [.gray])
            .chartXScale(domain: cal.startOfDay(for: from)...cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 5)) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel(format: range == .week ? .dateTime.weekday(.abbreviated) : .dateTime.day().month(.abbreviated))
                }
            }
            .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(.white.opacity(0.08)); AxisValueLabel() } }
            .frame(height: 220)
        }
    }

    private var routesMap: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Routes flown")
            Map(initialPosition: .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 30, longitude: 0), distance: 30_000_000, heading: 0, pitch: 0))) {
                ForEach(model.records.suffix(200)) { r in
                    MapPolyline(coordinates: Geo.path(r.origin.coordinate, r.destination.coordinate, segments: 32).map(\.cl))
                        .stroke(Color(hex: model.category(r.categoryID)?.colorHex ?? "#888").opacity(0.85), lineWidth: 1.5)
                }
            }
            .mapStyle(.imagery(elevation: .realistic))
            .mapControls {}
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var entries: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Flights")
            if model.records.isEmpty {
                Text("Your flights will appear here after you land.").font(.system(size: 13)).foregroundStyle(Theme.dim)
            }
            ForEach(model.records.sorted { $0.startedAt > $1.startedAt }.prefix(100)) { r in
                HStack(spacing: 10) {
                    Button { model.setGoalDone(r.id, !r.goalDone) } label: {
                        Image(systemName: r.goalDone ? "checkmark.circle.fill" : "circle").foregroundStyle(r.goalDone ? Theme.accent : Theme.faint)
                    }
                    .buttonStyle(.plain).accessibilityLabel(r.goalDone ? "Goal done" : "Mark goal done")
                    Circle().fill(Color(hex: model.category(r.categoryID)?.colorHex ?? "#888")).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.goal).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text("\(r.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(r.origin.code) → \(r.destination.code)\(r.outcome == .endedEarly ? " · ended early" : "")")
                            .font(.system(size: 11)).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Text(TimeFormat.duration(minutes: r.focusSeconds / 60)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.dim)
                    Menu {
                        Button("Edit goal…") { editing = r }
                        Button("Delete…", role: .destructive) { deleting = r }
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.04)))
            }
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "contrail-logbook.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Logbook.csv(model.records, categories: model.categories).write(to: url, atomically: true, encoding: .utf8) }
        catch { model.show("Could not save the CSV: \(error.localizedDescription)") }
    }
}

struct GoalEditor: View {
    let record: FlightRecord
    @Bindable var model: AppModel
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit goal").font(.headline)
            TextField("Goal", text: $text, axis: .vertical).lineLimit(2...4)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    if let i = model.records.firstIndex(where: { $0.id == record.id }) { model.records[i].goal = String(text.prefix(140)) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 380)
        .onAppear { text = record.goal }
    }
}
