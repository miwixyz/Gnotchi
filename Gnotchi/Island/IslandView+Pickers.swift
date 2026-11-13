import SwiftUI

// 0.21.0 (specs/2026-11-06-gnotchi-0.21.0-wachbleiben-timer.md): Timer-Auswahl mit Lineal und „Wach bleiben“ in der
// großen Insel. Beide brauchen mehr Höhe als die übrige große Insel (IslandGeometry.timerPickerHeight/awakeHeight).

/// Kleiner Kapsel-Knopf im Systemstil der Insel.
private struct IslandPill: View {
    let text: String
    var selected = false
    var width: CGFloat?
    /// Gewählt deutlich (weiß gefüllt, dunkle Schrift) – für Ein/Aus-Wahl wie Tage oder Mit/Ohne Maus (09.11.:
    /// 0,24 gegen 0,10 Deckkraft war kaum zu unterscheiden).
    var strong = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: text).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(strong && selected ? Color.black : .white.opacity(selected ? 1 : 0.85))
                .frame(maxWidth: width == nil ? .infinity : nil).frame(width: width, height: 26)
                .background(Capsule().fill(.white.opacity(selected ? (strong ? 0.9 : 0.24) : (strong ? 0.16 : 0.10))))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct RoundButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(Circle().fill(.white.opacity(0.12))).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
    }
}

// MARK: - Timer

/// Timer-Auswahl (Michael 06.11., Screenshot): Name + Start, „− 25 min +“ mit Lineal zum Ziehen, Voreinstellungen.
struct TimerPicker: View {
    let onStart: (Int, String?) -> Void
    @AppStorage(CountdownTimer.customKey) private var minutes = 25
    @State private var name = ""
    @State private var dragStart: Int?
    nonisolated static let presets = [1, 5, 10, 25, 45, 60]
    /// Punkte je Minute auf dem Lineal.
    nonisolated static let pointsPerMinute: CGFloat = 9

    /// Ziehweg → Minuten (getestet): nach rechts ziehen = weniger (das Lineal läuft mit dem Finger), 1…180.
    nonisolated static func minutes(start: Int, dragX: CGFloat) -> Int {
        CountdownTimer.clampCustom(start - Int((dragX / pointsPerMinute).rounded()))
    }

    nonisolated static func presetLabel(_ m: Int) -> String { m % 60 == 0 ? "\(m / 60)h" : "\(m)m" }

    var body: some View {
        let value = CountdownTimer.clampCustom(minutes)
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                TextField("Name (optional)", text: $name)
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.10)))
                    .onChange(of: name) { if name.count > CountdownTimer.nameLimit { name = String(name.prefix(CountdownTimer.nameLimit)) } }
                    .onSubmit { onStart(value, CountdownTimer.cleanName(name)) }
                Button { onStart(value, CountdownTimer.cleanName(name)) } label: {
                    Label("Start", systemImage: "play.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 32)
                        .background(Capsule().fill(.white.opacity(0.18))).contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                RoundButton(symbol: "minus", label: "Eine Minute weniger") { minutes = CountdownTimer.stepCustom(value, up: false) }
                VStack(spacing: 2) {
                    Text(verbatim: "\(value) min").font(.system(size: 20, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                    ruler(value)
                }
                RoundButton(symbol: "plus", label: "Eine Minute mehr") { minutes = CountdownTimer.stepCustom(value, up: true) }
            }
            // Porter-Optik (13.11.2026): die helle Auswahl gleitet zwischen den Voreinstellungen.
            SlidingPicker(Self.presets, selection: Binding(get: { value }, set: { minutes = $0 }),
                          height: 26, track: false, spacing: 6, segmentPadding: 0,
                          palette: SlidingPickerPalette(selectedText: .white, text: .white.opacity(0.85),
                                                        ghost: .white, ghostOpacity: 0.08,
                                                        pillFill: .white.opacity(0.18))) { m, _ in
                Text(verbatim: Self.presetLabel(m)).font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .background(Capsule().fill(.white.opacity(0.10)))
                    .accessibilityLabel(Text(verbatim: "\(m) Minuten"))
            }
        }
        .padding(.horizontal, 16)
    }

    /// Striche je Minute, längere je 5 Min.; die Mitte ist der gewählte Wert. Ziehen ändert ihn.
    private func ruler(_ value: Int) -> some View {
        Canvas { ctx, size in
            let mid = size.width / 2
            let span = Int(size.width / Self.pointsPerMinute / 2) + 1
            for m in (value - span)...(value + span) where CountdownTimer.customRange.contains(m) {
                let x = mid + CGFloat(m - value) * Self.pointsPerMinute
                let long = m % 5 == 0
                let h: CGFloat = m == value ? size.height : (long ? size.height * 0.7 : size.height * 0.4)
                let fade = 1 - min(1, abs(x - mid) / mid) * 0.8
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x, y: size.height - h))
                ctx.stroke(p, with: .color(.white.opacity((m == value ? 1 : 0.5) * fade)), lineWidth: m == value ? 2 : 1)
            }
        }
        .frame(height: 22)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 1)
            .onChanged { g in
                let start = dragStart ?? value
                dragStart = start
                minutes = Self.minutes(start: start, dragX: g.translation.width)
            }
            .onEnded { _ in dragStart = nil })
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "Zeit \(value) Minuten"))
        .accessibilityAdjustableAction { dir in
            minutes = CountdownTimer.stepCustom(value, up: dir == .increment)
        }
    }
}

// MARK: - Wach bleiben

struct AwakeView: View {
    @Bindable var awake: StayAwake
    /// nil = Hilfsprogramm nicht verbunden, false = ohne Freigabe.
    let helperTrusted: Bool?
    nonisolated static let dayOrder = [2, 3, 4, 5, 6, 7, 1]
    nonisolated static let dayNames = [1: "So", 2: "Mo", 3: "Di", 4: "Mi", 5: "Do", 6: "Fr", 7: "Sa"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { awake.isActive ? awake.turnOff() : awake.turnOn(hours: nil) } label: {
                    Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(awake.isActive ? .orange : .white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.white.opacity(awake.isActive ? 0.22 : 0.10))).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: awake.isActive ? "Wach bleiben ausschalten" : "Wach bleiben einschalten"))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "Wach bleiben").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text(verbatim: status).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 4)
                ForEach(StayAwake.durations, id: \.label) { d in
                    IslandPill(text: d.label, width: 54) { awake.turnOn(hours: d.hours) }
                }
            }
            // Raster (Michael 09.11.: „unübersichtlich“): Beschriftung links in fester Spalte, Bedienung daneben.
            row("Zeitplan") {
                Toggle("", isOn: $awake.schedule).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    .accessibilityLabel(Text(verbatim: "Zeitplan"))
                HStack(spacing: 4) {
                    ForEach(Self.dayOrder, id: \.self) { d in
                        IslandPill(text: Self.dayNames[d] ?? "", selected: awake.days.contains(d), width: 32, strong: true) {
                            if awake.days.contains(d) { awake.days.remove(d) } else { awake.days.insert(d) }
                        }
                    }
                }
                .padding(.leading, 6)
            }
            row("Uhrzeit") {
                stepper(awake.from, down: { awake.from = max(0, awake.from - StayAwake.step) },
                        up: { awake.from = min(awake.to - StayAwake.step, awake.from + StayAwake.step) })
                Text(verbatim: "bis").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                stepper(awake.to, down: { awake.to = max(awake.from + StayAwake.step, awake.to - StayAwake.step) },
                        up: { awake.to = min(1440, awake.to + StayAwake.step) })
                Text(verbatim: "mit Maus").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8)).padding(.leading, 4)
            }
            // Bewusst nicht abgeblendet, wenn der Zeitplan aus ist: Auf hellem Glas war das unlesbar (Michael 09.11.);
            // ob er läuft, zeigen Schalter und Statuszeile. So lässt er sich auch vorab einstellen.
            row("Außerhalb") {
                choice(awake.outside, off: "Normal schlafen", on: "Wach, Bildschirm aus") { awake.outside = $0 }
            }
            // „Ohne Zeitplan“ statt „Von Hand“ (Michael 09.11.: „Was heißt von Hand?“) – gilt für Tasse und Dauer-Knöpfe.
            row("Ohne Zeitplan") {
                choice(awake.nudge, off: "Ohne Maus", on: "Mit Maus") { awake.nudge = $0 }
                if awake.needsHelper, helperTrusted == false {
                    Text(verbatim: "Freigabe fehlt").font(.system(size: 11))
                        .foregroundStyle(.orange).lineLimit(1).padding(.leading, 6)
                        .help(Text(verbatim: "„Gnotchi Mitteilungen“ braucht die Freigabe unter Bedienungshilfen"))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    /// Eine Zeile im Raster: Beschriftung 90 pt breit (passt „Ohne Zeitplan“), dann die Bedienung, links bündig.
    private func row(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                .lineLimit(1).frame(width: 90, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    /// Zwei Möglichkeiten nebeneinander, die gewählte weiß gefüllt.
    private func choice(_ value: Bool, off: String, on: String, set: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 4) {
            IslandPill(text: off, selected: !value, width: 140, strong: true) { set(false) }
            IslandPill(text: on, selected: value, width: 140, strong: true) { set(true) }
        }
    }

    private var status: String {
        guard let until = awake.activeUntil else { return awake.schedule ? "Aus · Zeitplan wartet" : "Aus" }
        let how = awake.mode == .mouse ? "An mit Maus" : "An ohne Maus"
        if until == .distantFuture { return "\(how), bis du ausschaltest" }
        let time = Calendar.current.isDateInToday(until)
            ? until.formatted(date: .omitted, time: .shortened)
            : until.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        return "\(how) bis \(time)"
    }

    private func stepper(_ minutes: Int, down: @escaping () -> Void, up: @escaping () -> Void) -> some View {
        HStack(spacing: 2) {
            RoundButton(symbol: "minus", label: "15 Minuten früher", action: down)
            Text(verbatim: StayAwake.timeText(minutes)).font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white).frame(width: 44)
            RoundButton(symbol: "plus", label: "15 Minuten später", action: up)
        }
    }
}
