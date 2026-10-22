// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// Create a profile from the current configuration, or edit an existing one.
struct ProfileEditorSheet: View {
    enum Mode: Identifiable {
        case create
        case edit(Profile)

        var id: String {
            switch self {
            case .create: "create"
            case let .edit(profile): profile.id.uuidString
            }
        }
    }

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    let mode: Mode

    @State private var name = ""
    @State private var color: ProfileColor = .indigo
    @State private var symbolName = Profile.defaultSymbol
    @State private var applyOnConnect = false

    private var isEditing: Bool {
        if case .edit = mode {
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text(isEditing ? "Editar perfil" : "Novo perfil")
                .font(.title2.weight(.bold))
            TextField("Nome do perfil", text: $name, prompt: Text("Ex.: Trabalho, Jogos, Filmes"))
                .textFieldStyle(.roundedBorder)
            colorPicker
            symbolPicker
            Toggle("Aplicar ao conectar o monitor", isOn: $applyOnConnect)
                .toggleStyle(.switch)
            if !isEditing {
                captureSummary
            }
            buttons
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(width: 460)
        .onAppear(perform: load)
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Cor")
                .font(.callout.weight(.semibold))
            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(ProfileColor.allCases) { option in
                    Button {
                        color = option
                    } label: {
                        Circle()
                            .fill(DesignTokens.color(for: option))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.primary.opacity(color == option ? 0.6 : 0), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(option.rawValue))
                    .accessibilityAddTraits(color == option ? [.isSelected] : [])
                }
            }
        }
    }

    private var symbolPicker: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Ícone")
                .font(.callout.weight(.semibold))
            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(Profile.symbolChoices, id: \.self) { symbol in
                    Button {
                        symbolName = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.title3)
                            .frame(width: 34, height: 34)
                            .background(symbolBackground(for: symbol), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(symbol))
                    .accessibilityAddTraits(symbolName == symbol ? [.isSelected] : [])
                }
            }
        }
    }

    private var captureSummary: some View {
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Será salvo")
                    .font(.callout.weight(.semibold))
                ForEach(container.monitors.displays) { display in
                    Text("\(display.name): \(display.currentSettings.summary)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button("Cancelar") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isEditing ? "Salvar" : "Criar perfil") { save() }
                .buttonStyle(.vibrant)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func symbolBackground(for symbol: String) -> Color {
        symbolName == symbol ? DesignTokens.color(for: color).opacity(0.25) : Color.clear
    }

    private func load() {
        if case let .edit(profile) = mode {
            name = profile.name
            color = profile.color
            symbolName = profile.symbolName
            applyOnConnect = profile.applyOnConnect
        }
    }

    private func save() {
        switch mode {
        case .create:
            container.profiles.saveCurrent(name: name, color: color, symbolName: symbolName, applyOnConnect: applyOnConnect)
        case let .edit(profile):
            var updated = profile
            updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.color = color
            updated.symbolName = symbolName
            updated.applyOnConnect = applyOnConnect
            container.profiles.update(updated)
        }
        dismiss()
    }
}
