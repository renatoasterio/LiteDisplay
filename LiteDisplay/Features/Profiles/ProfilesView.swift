// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// Saved profiles: apply, edit, delete and save the current configuration as a new one.
struct ProfilesView: View {
    @Environment(AppContainer.self) private var container
    @State private var isCreating = false
    @State private var editing: Profile?

    private var profiles: ProfilesViewModel {
        container.profiles
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                GradientHero(
                    title: String(localized: "Perfis"),
                    subtitle: String(localized: "Guarde combinações de nitidez, tamanho e taxa e aplique com um clique, aqui ou pelo menu.")
                ) {
                    Button("Salvar configuração atual…", systemImage: "plus") { isCreating = true }
                        .buttonStyle(.vibrant)
                        .disabled(container.monitors.displays.isEmpty)
                }
                if let error = profiles.error {
                    ErrorBanner(error: error) { profiles.dismissMessages() }
                }
                if let notice = profiles.notice {
                    NoticeBanner(text: notice) { profiles.dismissMessages() }
                }
                if profiles.profiles.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                            Text("Nenhum perfil ainda")
                                .font(.headline)
                            Text("Configure o monitor do jeito que gosta e salve como perfil.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text("Marque “Aplicar ao conectar” para o LiteDisplay restaurar tudo sozinho.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ForEach(profiles.profiles) { profile in
                        ProfileCard(profile: profile, isApplying: profiles.isApplying) {
                            Task { await profiles.apply(profile) }
                        } onEdit: {
                            editing = profile
                        } onDelete: {
                            profiles.delete(profile)
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { profiles.reload() }
        .sheet(isPresented: $isCreating) {
            ProfileEditorSheet(mode: .create)
        }
        .sheet(item: $editing) { profile in
            ProfileEditorSheet(mode: .edit(profile))
        }
    }
}

private struct ProfileCard: View {
    @Environment(AppContainer.self) private var container
    let profile: Profile
    let isApplying: Bool
    let onApply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(DesignTokens.color(for: profile.color).opacity(0.2))
                    Image(systemName: profile.symbolName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(DesignTokens.color(for: profile.color))
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Text(profile.name)
                            .font(.headline)
                        if profile.applyOnConnect {
                            Chip(text: String(localized: "Ao conectar"), systemImage: "bolt.fill", tint: .brandCyan)
                        }
                    }
                    ForEach(profile.displays.sorted(by: { $0.key < $1.key }), id: \.key) { entry in
                        HStack(spacing: DesignTokens.Spacing.xs) {
                            Circle()
                                .fill(DesignTokens.color(for: entry.value.method))
                                .frame(width: 6, height: 6)
                            Text(displayName(for: entry.key))
                                .font(.callout)
                            Text(entry.value.summary)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Button("Aplicar", action: onApply)
                        .buttonStyle(.vibrant)
                        .disabled(isApplying)
                    Menu {
                        Button("Editar…", systemImage: "pencil", action: onEdit)
                        Button("Excluir", systemImage: "trash", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                    .accessibilityLabel(Text("Mais ações"))
                }
            }
        }
    }

    private func displayName(for persistentID: String) -> String {
        container.monitors.displays.first { $0.persistentID == persistentID }?.name ?? String(localized: "Monitor desconectado")
    }
}
