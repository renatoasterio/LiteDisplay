// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

struct SidebarView: View {
    @Environment(AppContainer.self) private var container
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Monitores") {
                if container.monitors.displays.isEmpty {
                    Label("Nenhum monitor externo", systemImage: "display.trianglebadge.exclamationmark")
                        .foregroundStyle(.secondary)
                }
                ForEach(container.monitors.displays) { display in
                    DisplayRow(display: display)
                        .tag(SidebarItem.display(display.id))
                }
            }
            Section("LiteDisplay") {
                Label("Perfis", systemImage: "rectangle.stack")
                    .tag(SidebarItem.profiles)
                Label("Ajustes", systemImage: "slider.horizontal.3")
                    .tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Circle()
                    .fill(DesignTokens.brandGradient)
                    .frame(width: 10, height: 10)
                Text("LiteDisplay \(container.preferences.appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
        }
    }
}

private struct DisplayRow: View {
    let display: DisplaySnapshot

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Circle()
                .fill(DesignTokens.color(for: display.activeMethod))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(display.name)
                    .lineLimit(1)
                Text(display.currentMode?.summary ?? String(localized: "Sem modo"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
