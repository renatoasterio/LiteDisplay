// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// App-wide preferences.
struct SettingsView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                GradientHero(
                    title: String(localized: "Ajustes"),
                    subtitle: String(localized: "Texto, inicialização e comportamento ao conectar monitores.")
                ) { EmptyView() }
                if let error = container.preferences.error {
                    ErrorBanner(error: error) { container.preferences.error = nil }
                }
                SectionHeader(title: String(localized: "Texto"), systemImage: "textformat")
                TextSettingsCard(preferences: container.preferences)
                SectionHeader(title: String(localized: "Sistema"), systemImage: "macwindow")
                SystemSettingsCard(preferences: container.preferences)
                SectionHeader(title: String(localized: "Sobre"), systemImage: "info.circle")
                AboutCard(version: container.preferences.appVersion)
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { container.preferences.refresh() }
    }
}

private struct TextSettingsCard: View {
    let preferences: SettingsViewModel

    var body: some View {
        Card {
            Toggle(isOn: Binding(
                get: { preferences.isStrongFontSmoothing },
                set: { preferences.setStrongFontSmoothing($0) }
            )) {
                SettingLabel(
                    title: String(localized: "Suavização de fontes mais forte"),
                    detail: String(
                        localized: "Engrossa levemente o texto em monitores sem HiDPI. Vale para apps abertos a partir de agora."
                    )
                )
            }
            .toggleStyle(.switch)
        }
    }
}

private struct SystemSettingsCard: View {
    @Bindable var preferences: SettingsViewModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                Toggle(isOn: Binding(
                    get: { preferences.launchAtLogin },
                    set: { preferences.setLaunchAtLogin($0) }
                )) {
                    SettingLabel(
                        title: String(localized: "Iniciar no login"),
                        detail: String(localized: "Mantém a tela virtual e a restauração automática disponíveis desde o início da sessão.")
                    )
                }
                .toggleStyle(.switch)
                if preferences.loginRequiresApproval {
                    Button("Aprovar em Ajustes do Sistema…") { preferences.openLoginItemsSettings() }
                        .buttonStyle(.pill)
                }
                Divider()
                Toggle(isOn: $preferences.reapplyOnConnect) {
                    SettingLabel(
                        title: String(localized: "Restaurar ao conectar"),
                        detail: String(localized: "Reaplica o perfil marcado “ao conectar” ou a última configuração usada no monitor.")
                    )
                }
                .toggleStyle(.switch)
                Divider()
                Toggle("Mostrar a janela ao abrir o app", isOn: $preferences.showsWindowAtLaunch)
                    .toggleStyle(.switch)
            }
        }
    }
}

private struct AboutCard: View {
    let version: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("LiteDisplay \(version)")
                    .font(.headline)
                Text("Texto nítido em monitores Full HD no Mac. Sem rede, sem telemetria: tudo acontece no seu Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
