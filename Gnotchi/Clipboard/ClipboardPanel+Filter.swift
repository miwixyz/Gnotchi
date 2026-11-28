import SwiftUI

// MARK: - Filter nach Quell-App und Zeitraum (0.49.0)

extension ClipboardPanelView {
    /// Knopf im Suchkopf. Aktiv: gefülltes Symbol und Kurzform („Mail · 7 Tage“) daneben.
    var filterMenu: some View {
        let filter = state.filter
        return Menu {
            Picker("Zeitraum", selection: $state.filter.period) {
                ForEach(ClipFilter.Period.allCases) { Text(verbatim: $0.label).tag($0) }
            }
            .pickerStyle(.inline)
            Picker("App", selection: $state.filter.sourceBundleID) {
                Text("Alle Apps").tag(String?.none)
                ForEach(menuSources(filter), id: \.self) { id in
                    Text(verbatim: AppIcons.name(for: id) ?? id).tag(String?.some(id))
                }
            }
            .pickerStyle(.inline)
            if filter.isActive {
                Divider()
                Button("Filter zurücksetzen") { state.filter = ClipFilter() }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill"
                                                  : "line.3.horizontal.decrease.circle")
                    .foregroundStyle(filter.isActive ? Color.accentColor : .secondary)
                if filter.isActive {
                    Text(verbatim: summary(filter)).font(.system(size: 11)).lineLimit(1)
                }
            }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Nach App und Zeitraum filtern")
        .accessibilityLabel(Text(filter.isActive ? "Filter: \(summary(filter))" : "Filter"))
    }

    /// Höchstens 15 Apps; die gewählte steht immer drin (sonst hätte der Picker keinen passenden Eintrag, etwa nach
    /// dem Wechsel in eine Sammlung ohne Einträge dieser App).
    private func menuSources(_ filter: ClipFilter) -> [String] {
        var list = Array(state.filterSources.prefix(15))
        if let chosen = filter.sourceBundleID, !list.contains(chosen) { list.append(chosen) }
        return list
    }

    private func summary(_ filter: ClipFilter) -> String {
        let app = filter.sourceBundleID.map { AppIcons.name(for: $0) ?? $0 }
        return [app, filter.period == .all ? nil : filter.period.shortLabel].compactMap(\.self).joined(separator: " · ")
    }
}
