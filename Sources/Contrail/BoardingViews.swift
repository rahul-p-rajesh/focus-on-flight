import ContrailCore
import SwiftUI

struct BoardingPassView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let plan = model.boardingPlan {
            let realMinutes = plan.duration * model.timeScale / 60
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("BOARDING PASS").font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(Theme.faint)
                    Spacer()
                    Text("CONTRAIL").font(.system(size: 11, weight: .heavy)).tracking(3).foregroundStyle(Theme.accent.opacity(0.8))
                }
                HStack(alignment: .center) {
                    endpoint(plan.origin, align: .leading)
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "airplane").font(.system(size: 20)).foregroundStyle(Theme.accent)
                        Text(TimeFormat.duration(minutes: realMinutes)).font(.system(size: 13, weight: .medium, design: .monospaced))
                        Text(model.settings.units.format(plan.distanceKm)).font(.system(size: 11)).foregroundStyle(Theme.faint)
                    }
                    Spacer()
                    endpoint(plan.destination, align: .trailing)
                }
                Perforation()
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                        GridRow {
                            field("Seat", "\(plan.seat) · window")
                            field("Category", model.category(plan.categoryID)?.name ?? "—")
                            field("Departs", ctx.date.formatted(date: .omitted, time: .shortened))
                            field("Lands", ctx.date.addingTimeInterval(plan.duration).formatted(date: .omitted, time: .shortened))
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("Goal")
                    Text(plan.goal).font(.system(size: 15, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    optionRow("Landing chime", $model.settings.chimeOn)
                    optionRow("Desktop mode: fly behind your windows", $model.desktopMode)
                }
                .font(.system(size: 13))
                HStack {
                    Button("Back") { model.backToPlanning() }.buttonStyle(SecondaryButtonStyle())
                    SoundButton(model: model)
                    Spacer()
                    Button("Board and take off") { model.takeOff() }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.return, modifiers: [])
                }
            }
            .padding(28)
            .frame(width: 620)
            .glassPanel(radius: 28)
        }
    }

    private func endpoint(_ p: Place, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 3) {
            HStack(spacing: 4) {
                Text(p.code).font(.system(size: 40, weight: .light, design: .monospaced))
                if p.isMadeUp { MadeUpMark() }
            }
            Text(p.name).font(.system(size: 12, weight: .medium)).lineLimit(1).frame(maxWidth: 200, alignment: align == .leading ? .leading : .trailing)
            if let l = p.locality { Text(l).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1) }
        }
    }

    private func optionRow(_ text: String, _ value: Binding<Bool>) -> some View {
        HStack {
            Text(text)
            Spacer()
            Toggle(text, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }

    private func field(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(k)
            Text(v).font(.system(size: 14, weight: .medium, design: .monospaced))
        }
    }
}

struct Perforation: View {
    var body: some View {
        Line().stroke(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 5])).frame(height: 1)
            .padding(.horizontal, -28)
    }
    struct Line: Shape {
        func path(in r: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: 0, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
    }
}

struct LandedView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let r = model.lastRecord {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: r.outcome == .landed ? "airplane.arrival" : "airplane.circle")
                        .font(.system(size: 26)).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.outcome == .landed ? "Welcome to \(r.destination.name)" : "Flight ended early")
                            .font(.system(size: 20, weight: .semibold))
                        Text("\(r.origin.code) → \(r.destination.code) · seat \(r.seat)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.dim)
                    }
                }
                HStack(spacing: 28) {
                    stat("Time", TimeFormat.duration(minutes: r.focusSeconds / 60))
                    stat("Flown", model.settings.units.format(r.distanceKm * min(1, r.flownSeconds / max(r.plannedSeconds, 1))))
                    stat("Category", model.category(r.categoryID)?.name ?? "—")
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Goal")
                    Toggle(isOn: Binding(get: { model.lastRecord?.goalDone ?? false }, set: { model.setGoalDone(r.id, $0) })) {
                        Text(r.goal).font(.system(size: 15, weight: .medium))
                    }
                    .toggleStyle(.checkbox)
                }
                if r.outcome == .endedEarly && r.flownSeconds < 60 {
                    Text("Flights shorter than a minute are not saved to the logbook.").font(.system(size: 11)).foregroundStyle(Theme.faint)
                }
                HStack {
                    Button("Open logbook") { model.tab = .logbook; model.planNext(continueJourney: true) }.buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Button("Plan next flight from \(r.destination.code)") { model.planNext(continueJourney: true) }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(28)
            .frame(width: 560)
            .glassPanel(radius: 28)
        }
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(k)
            Text(v).font(.system(size: 16, weight: .medium, design: .monospaced))
        }
    }
}
