// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// Every usable mode, searchable, with an apply button per row.
struct ModeTableView: View {
    let display: DisplaySnapshot
    let onApply: (DisplayMode) -> Void

    @State private var query = ""
    @State private var hiDPIOnly = false

    private var rows: [DisplayMode] {
        display.modes.filter { mode in
            (!hiDPIOnly || mode.isHiDPI) && (query.isEmpty || mode.summary.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                TextField("Filtrar modos", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Toggle("Só HiDPI", isOn: $hiDPIOnly)
                    .toggleStyle(.switch)
                Spacer()
                Text("\(rows.count) modos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Table(rows) {
                TableColumn("Parece") { mode in
                    Text(mode.size.description)
                        .fontWeight(mode.id == display.currentMode?.id ? .bold : .regular)
                }
                TableColumn("Pixels") { mode in Text(mode.pixelSize.description) }
                TableColumn("Hz") { mode in Text(mode.refreshRate.hertzLabel) }
                TableColumn("Escala") { mode in
                    Chip(text: mode.isHiDPI ? "HiDPI" : "1x", tint: mode.isHiDPI ? .statusHiDPI : .statusLowRes)
                }
                TableColumn("") { mode in
                    if mode.id == display.currentMode?.id {
                        Label("Atual", systemImage: "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.statusHiDPI)
                    } else {
                        Button("Aplicar") { onApply(mode) }
                            .buttonStyle(.pill)
                    }
                }
                .width(90)
            }
            .frame(minHeight: 260, maxHeight: 420)
        }
    }
}
