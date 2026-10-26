import AppKit
import SwiftUI

// MARK: - Herunterklappen aus der Notch (0.14.0, specs/2026-10-26-gnotchi-0.14.0-kartenbild.md)

extension ClipboardPanelView {
    var dropBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear.frame(height: state.topInset)
            HStack(spacing: 8) {
                header
                if let expand = state.onExpand {
                    Button(action: expand) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("Große Ansicht (Kürzel nochmal drücken)")
                    .accessibilityLabel(Text("Mehr – große Ansicht"))
                }
            }
            pills
            row
            if link.secretsToOffer > 0 {
                compactSecretOffer(link.secretsToOffer)
            } else if let message = state.message {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(link.canPaste ? "Doppelklick oder ↵ fügt ein · ⇧ reiner Text · ←/→ · Kürzel nochmal: mehr · Esc"
                                   : "↵ kopieren · ⇧↵ reiner Text · ←/→ · Kürzel nochmal: mehr · Esc · danach ⌘V")
                    .font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous)
            .fill(.black))
        .environment(\.colorScheme, .dark)
        .onAppear { searchFocused = true }
        .onHover { state.hover($0) }
    }

    /// Sammlungen als Pillen mit Name und Anzahl (Michael: Name sichtbar; hier ist Platz).
    private var pills: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    pill(Pill(symbol: "clock", name: String(localized: "Verlauf"), count: store?.entries().count ?? 0,
                              color: .secondary), selected: state.collectionID == nil) { state.collectionID = nil }
                    ForEach(store?.collections() ?? [], id: \.id) { c in
                        pill(Pill(symbol: c.isVault ? "lock.fill" : c.symbol, name: c.name, count: c.entries?.count ?? 0,
                                  color: c.color.swiftUI), selected: state.collectionID == c.id) { state.collectionID = c.id }
                            .dropDestination(for: String.self) { ids, _ in drop(ids, on: c) }
                            .contextMenu {
                                if !c.isPinned {
                                    Button("Sammlung löschen …", role: .destructive) { deleteCollection(c) }
                                }
                            }
                    }
                }
            }
            Menu {
                Button("Neue Sammlung …") { newCollection(vault: false) }
                Button("Neuer Tresor …") { newCollection(vault: true) }
            } label: { Image(systemName: "plus") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
        }
        .frame(height: 26)
    }

    struct Pill {
        let symbol: String
        let name: String
        let count: Int
        let color: Color
    }

    private func pill(_ p: Pill, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: p.symbol).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selected ? Color.black : p.color)
                Text(verbatim: p.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(verbatim: "\(p.count)").font(.system(size: 10)).opacity(0.6)
            }
            .foregroundStyle(selected ? Color.black : Color.white)
            .padding(.horizontal, 10).frame(height: 24)
            .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(p.name), \(p.count)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Eine waagrechte Kartenreihe mit „Heute“/„Gestern“-Trennern.
    @ViewBuilder private var row: some View {
        let list = state.entries
        if list.isEmpty {
            Text(state.query.isEmpty ? "Noch nichts kopiert" : "Nichts gefunden")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: ClipTile.size.height + 18)
        } else {
            let index = Dictionary(uniqueKeysWithValues: list.enumerated().map { ($1.id, $0) })
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(ClipDays.group(list)) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: group.label).font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    ForEach(group.entries, id: \.id) { entry in tile(entry, at: index[entry.id] ?? 0) }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onChange(of: state.selection) {
                    if list.indices.contains(state.selection) { proxy.scrollTo(list[state.selection].id) }
                }
            }
            .frame(height: ClipTile.size.height + 22)
        }
    }

    private func tile(_ entry: ClipEntry, at i: Int) -> some View {
        ClipTile(link: link, entry: entry, number: i < 9 ? i + 1 : nil, selected: i == state.selection)
            .id(entry.id)
            .onTapGesture(count: 2) { state.pick(entry, plain: NSEvent.modifierFlags.contains(.shift)) }
            .simultaneousGesture(TapGesture().onEnded { state.select(entry) })
            .contextMenu { menu(for: entry) }
    }

    private func compactSecretOffer(_ count: Int) -> some View {
        HStack(spacing: 8) {
            Label(count == 1 ? "1 Schlüssel offen in Sammlungen" : "\(count) Schlüssel offen in Sammlungen",
                  systemImage: "key.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
            Button("Alle in den Tresor") {
                link.moveSavedSecretsToVault { moved in
                    state.message = moved.map { String(localized: "\($0) in den Tresor verschoben.") }
                        ?? String(localized: "Tresor nicht entsperrt.")
                }
            }
            Button("Später") { link.dismissSecretOffer() }
        }
        .font(.system(size: 11)).buttonStyle(.borderless)
    }
}
