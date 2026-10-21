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

// MARK: Große Insel – „Eine Sache groß“ (0.5.0, Michael 21.10.: „Notch zu klein für die vielen Infos“)

/// Symbolleiste über der großen Sache: je Aktivität ein Symbol (die gezeigte hervorgehoben, Klick wechselt),
/// rechts Mikrofon/Kamera-Punkte und das Qotti-Kontingent. Nur Symbole und feste Texte.
struct ChipRow: View {
    let items: [LiveActivity]
    let current: LiveActivity?
    let event: KalliEvents.Event?
    let headphones: Headphones?
    let mediaApp: String?
    let privacy: ActivityModel.Privacy
    let quota: String?
    /// nil = Spiegel ausgeschaltet; sonst ob er gerade gezeigt wird.
    var mirror: Bool?
    let onSelect: (LiveActivity) -> Void
    var onMirror: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Button { onSelect(item) } label: {
                    chip(item)
                        .frame(width: 26, height: 18)
                        .background(Capsule().fill(.white.opacity(item == current ? 0.22 : 0)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: label(item)))
                .accessibilityAddTraits(item == current ? .isSelected : [])
            }
            if let mirror {
                Button(action: onMirror) {
                    Image(systemName: "person.crop.square").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(mirror ? .white : .secondary)
                        .frame(width: 26, height: 18)
                        .background(Capsule().fill(.white.opacity(mirror ? 0.22 : 0)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: "Spiegel"))
                .accessibilityAddTraits(mirror ? .isSelected : [])
            }
            Spacer(minLength: 0)
            if let quota {
                Text(verbatim: quota).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            if privacy.isActive { PrivacyDots(privacy: privacy) }
        }
        .frame(height: 20)
    }

    @ViewBuilder private func chip(_ item: LiveActivity) -> some View {
        let tint: Color = item == current ? .white : .secondary
        switch item {
        case .media:
            if let mediaApp { AppSymbol(bundleID: mediaApp, size: 14) } else { symbol("music.note", tint) }
        case .event:
            symbol("calendar", event?.color.map(Color.init(rgb:)) ?? tint)
        case .headphones:
            symbol(headphones?.symbol ?? "headphones", tint)
        case .update(let app):
            AppSymbol(bundleID: app.bundleID, size: 14)
        }
    }

    private func symbol(_ name: String, _ color: Color) -> some View {
        Image(systemName: name).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
    }

    private func label(_ item: LiveActivity) -> String {
        switch item {
        case .media: "Musik"
        case .event: "Termin"
        case .headphones: "Kopfhörer"
        case .update(let app): "Update \(app.name)"
        }
    }
}

/// Große Sache außer Musik, in Player-Größe (Michael 21.10.: Hinweis-Größe war zu klein): Symbol links,
/// Titel (bis zwei Zeilen) und eine Zeile darunter, rechts optional ein Knopf. Titel und Namen nur `Text(verbatim:)`.
struct ActivityCard<Leading: View>: View {
    let title: String
    let subtitle: String
    var action: String?
    var onTap: (() -> Void)?
    var height: CGFloat = IslandGeometry.expandedSize.height - 12
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        let content = HStack(spacing: 14) {
            leading().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(2).truncationMode(.tail)
                Text(verbatim: subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Text(verbatim: action).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).fixedSize()
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.18)))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: height)
        .contentShape(Rectangle())
        if let onTap {
            Button(action: onTap) { content }.buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: "\(title), \(subtitle), \(action ?? "")"))
        } else {
            content.accessibilityElement(children: .combine)
        }
    }
}

/// Termin groß: Kalender-Symbol in der Kalenderfarbe, Titel, „18:56 · in 10 Min“, Klick öffnet Apple Kalender.
struct EventCard: View {
    let event: KalliEvents.Event
    let onOpen: () -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            ActivityCard(title: event.title,
                         subtitle: "\(KalliEvents.timeText(event)) · in \(KalliEvents.minutesLeft(event, now: context.date)) Min",
                         action: "Kalender", onTap: onOpen, leading: {
                Image(systemName: "calendar").font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(event.color.map(Color.init(rgb:)) ?? .white)
            })
        }
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
