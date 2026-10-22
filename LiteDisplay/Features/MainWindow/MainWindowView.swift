// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// What the sidebar can select.
enum SidebarItem: Hashable {
    case display(UInt32)
    case profiles
    case settings
}

/// The main window: sidebar with monitors, profiles and settings; detail on the right.
struct MainWindowView: View {
    @Environment(AppContainer.self) private var container
    @State private var selection: SidebarItem?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: DesignTokens.Window.sidebarWidth, max: 300)
        } detail: {
            detail
        }
        .navigationTitle("LiteDisplay")
        .frame(minWidth: DesignTokens.Window.minWidth, minHeight: DesignTokens.Window.minHeight)
        .onAppear { selectFirstDisplayIfNeeded(container.monitors.displays) }
        .onChange(of: container.monitors.displays) { _, displays in selectFirstDisplayIfNeeded(displays) }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case let .display(id)?:
            if let display = container.monitors.display(withID: id) {
                MonitorDetailView(display: display)
                    .id(id)
            } else {
                NoDisplaysView()
            }
        case .profiles?:
            ProfilesView()
        case .settings?:
            SettingsView()
        case nil:
            NoDisplaysView()
        }
    }

    private func selectFirstDisplayIfNeeded(_ displays: [DisplaySnapshot]) {
        switch selection {
        case let .display(id)? where displays.contains(where: { $0.id == id }):
            return
        case .profiles?, .settings?:
            return
        default:
            selection = displays.first.map { .display($0.id) }
        }
    }
}

/// Shown when no external display is connected.
struct NoDisplaysView: View {
    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            MonitorGlyph(size: 96, tint: .brandIndigo)
            Text("Nenhum monitor externo conectado")
                .font(.title2.weight(.semibold))
            Text("Conecte um monitor para escolher a nitidez, a resolução e a taxa de atualização.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Spacing.xxl)
    }
}
