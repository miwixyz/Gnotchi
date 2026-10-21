import SwiftUI

// Live-Aktivitäten in der Insel (0.4.0, specs/2026-10-21-gnotchi-0.4.0-live-aktivitaeten.md).
// Gerätenamen vergibt der Nutzer frei, Titel kommen von beliebigen Websites → nur `Text(verbatim:)` (G5).
// Update-Texte nur aus festen Namen und geprüfter Version (G23).

/// Eine Zeile: farbiger Punkt (optional), Symbol, Text. Gemeinsam für Mikrofon/Kamera, Kopfhörer und Updates.
struct ActivityRow: View {
    var dot: Color?
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 14)
            Text(verbatim: text).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
        }
        .frame(height: 16)
        .accessibilityElement(children: .combine)
    }
}

/// Update einer Familien-App als Zeile, klickbar: öffnet die echte App (G24) bzw. Sparkle bei Gnotchi selbst.
struct UpdateLine: View {
    let entry: FamilyUpdates.Entry
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 5) {
                ActivityRow(symbol: "arrow.down.circle.fill", text: entry.label)
                Spacer(minLength: 0)
                Text(verbatim: "Öffnen").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(entry.label), öffnen"))
    }
}

/// Nächster Termin aus Kalli (0.5.0, G26) als Zeile, klickbar: öffnet Apple Kalender. Titel nur verbatim.
struct EventLine: View {
    let event: KalliEvents.Event
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            TimelineView(.everyMinute) { context in
                HStack(spacing: 5) {
                    ActivityRow(dot: event.color.map(Color.init(rgb:)), symbol: "calendar",
                                text: "\(KalliEvents.timeText(event)) · \(event.title)")
                    Spacer(minLength: 0)
                    Text(verbatim: "in \(KalliEvents.minutesLeft(event, now: context.date)) Min")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).fixedSize()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "Termin \(KalliEvents.timeText(event)), \(event.title), im Kalender öffnen"))
    }
}

/// Kleine Insel, Termin: Kalender-Symbol in der Kalenderfarbe, rechts „12 Min“; ohne Notch dazu „10:30 Titel“.
struct EventCompact: View {
    let event: KalliEvents.Event
    let privacy: ActivityModel.Privacy
    let pill: Bool
    let height: CGFloat
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            TimelineView(.everyMinute) { context in
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(event.color.map(Color.init(rgb:)) ?? .white).frame(width: 18)
                    if pill {
                        Text(verbatim: "\(KalliEvents.timeText(event)) \(event.title)")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                    if privacy.isActive {
                        PrivacyDots(privacy: privacy)
                    } else {
                        Text(verbatim: "\(KalliEvents.minutesLeft(event, now: context.date)) Min")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).fixedSize()
                    }
                }
            }
            .padding(.horizontal, pill ? 12 : 10)
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "Termin \(KalliEvents.timeText(event)), \(event.title), im Kalender öffnen"))
        .transition(.opacity)
    }
}

extension Color {
    init(rgb: KalliEvents.RGB) {
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

/// Große Insel ohne Musik: Termin, Kopfhörer, Updates, Mikrofon und Kamera untereinander, in Hinweis-Größe
/// (ab der dritten Zeile höher, IslandController.panelFrame).
struct ActivityDetails: View {
    var event: KalliEvents.Event?
    let headphones: Headphones?
    let updates: [FamilyUpdates.Entry]
    let privacy: ActivityModel.Privacy
    let topInset: CGFloat
    let height: CGFloat
    let onOpen: (FamilyApp) -> Void
    var onOpenEvent: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let event {
                EventLine(event: event, onOpen: onOpenEvent)
            }
            if let headphones {
                ActivityRow(symbol: headphones.symbol, text: headphones.name)
            }
            ForEach(updates, id: \.app) { e in
                UpdateLine(entry: e) { onOpen(e.app) }
            }
            if let apps = privacy.micLine {
                ActivityRow(dot: .orange, symbol: "mic.fill", text: apps)
            }
            if privacy.camera {
                ActivityRow(dot: .green, symbol: "video.fill", text: "Kamera")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .frame(height: height)
        .padding(.top, topInset)
        .transition(.opacity)
    }
}

/// Punkte für Mikrofon (orange) und Kamera (grün), wie macOS in der Menüleiste.
struct PrivacyDots: View {
    let privacy: ActivityModel.Privacy

    var body: some View {
        HStack(spacing: 3) {
            if privacy.mic { Circle().fill(.orange).frame(width: 6, height: 6) }
            if privacy.camera { Circle().fill(.green).frame(width: 6, height: 6) }
        }
        .frame(height: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: privacy.compactLabel ?? ""))
    }
}

/// Kleine Insel, Kopfhörer: mit Notch nur das Symbol im linken Flügel (40 pt fassen keinen Namen),
/// ohne Notch Symbol und Gerätename. Rechts die Mikrofon/Kamera-Punkte, falls aktiv.
struct HeadphonesCompact: View {
    let headphones: Headphones
    let privacy: ActivityModel.Privacy
    let pill: Bool
    let height: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: headphones.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 18)
            if pill {
                Text(verbatim: headphones.name).font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
            if privacy.isActive { PrivacyDots(privacy: privacy) }
        }
        .padding(.horizontal, pill ? 12 : 10)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Kopfhörer: \(headphones.name)"))
        .transition(.opacity)
    }
}

/// Kleine Insel, Update: App-Symbol aus dem lokalen Bundle, ohne Notch dazu „Kalli 0.11.0 bereit“.
/// Ein Klick öffnet die App (G24); Überfahren klappt wie sonst auf.
struct UpdateCompact: View {
    let entry: FamilyUpdates.Entry
    let privacy: ActivityModel.Privacy
    let pill: Bool
    let height: CGFloat
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                AppSymbol(bundleID: entry.app.bundleID, size: 18)
                if pill {
                    Text(verbatim: entry.label).font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 0)
                if privacy.isActive {
                    PrivacyDots(privacy: privacy)
                } else {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, pill ? 12 : 10)
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(entry.label), öffnen"))
        .transition(.opacity)
    }
}

/// App-Symbol aus dem lokalen Bundle (AppIcons, zwischengespeichert); ohne installierte App ein Platzhalter.
struct AppSymbol: View {
    let bundleID: String
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = AppIcons.icon(for: bundleID) {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app.badge").font(.system(size: size * 0.7)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Trackwechsel (0.4.0): 3 s breiter. Mit Notch links Cover und Titel, rechts Interpret und Pegel – die Mitte
/// verdeckt die Hardware. Ohne Notch Cover, „Titel · Interpret“ und Pegel in einer Zeile.
struct TrackFlash<Cover: View, Bars: View>: View {
    let info: NowPlayingInfo
    /// Breite der Notch; nil = Bildschirm ohne Notch.
    let notchWidth: CGFloat?
    let height: CGFloat
    @ViewBuilder let cover: () -> Cover
    @ViewBuilder let bars: () -> Bars

    var body: some View {
        HStack(spacing: 8) {
            cover()
            if let notchWidth {
                Text(verbatim: info.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: notchWidth)
                Text(verbatim: info.artist ?? "").font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Text(verbatim: [info.title, info.artist].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            bars()
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, 10)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [info.title, info.artist].compactMap { $0 }.joined(separator: ", ")))
        .transition(.opacity)
    }
}
