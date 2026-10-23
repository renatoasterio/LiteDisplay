// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import SwiftUI

/// Quick actions in the menu bar popover: per-display sharpness toggle, profiles and a way to the main window.
struct MenuBarMenuView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            header
            displays
            if !container.profiles.profiles.isEmpty {
                Divider()
                profiles
            }
            Divider()
            blueLight
            Divider()
            footer
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(width: DesignTokens.MenuBar.width)
        .onAppear { container.profiles.reload() }
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Circle()
                .fill(DesignTokens.brandGradient)
                .frame(width: 14, height: 14)
            Text("LiteDisplay")
                .font(.headline)
            Spacer()
            if container.monitors.isApplying {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var displays: some View {
        if container.monitors.displays.isEmpty {
            Label("Nenhum monitor externo conectado", systemImage: "display.trianglebadge.exclamationmark")
                .foregroundStyle(.secondary)
                .font(.callout)
        } else {
            ForEach(container.monitors.displays) { display in
                MenuDisplayRow(display: display)
            }
        }
        if let error = container.monitors.error {
            Text(error.errorDescription ?? "")
                .font(.caption)
                .foregroundStyle(Color.statusError)
        }
    }

    private var profiles: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Perfis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(container.profiles.profiles) { profile in
                Button {
                    Task { await container.profiles.apply(profile) }
                } label: {
                    HStack {
                        Image(systemName: profile.symbolName)
                            .foregroundStyle(DesignTokens.color(for: profile.color))
                            .frame(width: 18)
                        Text(profile.name)
                        Spacer()
                        Image(systemName: "arrow.right.circle")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(container.profiles.isApplying)
            }
        }
    }

    private var blueLight: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: container.comfort.isActiveNow ? "sun.haze.fill" : "sun.haze")
                .foregroundStyle(container.comfort.isActiveNow ? Color.statusLowRes : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text("Reduzir luz azul")
                    .font(.callout.weight(.semibold))
                Text(container.comfort.isEnabled ? container.comfort.kelvinLabel : String(localized: "Desligado"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Reduzir luz azul", isOn: Binding(
                get: { container.comfort.isEnabled },
                set: { container.comfort.isEnabled = $0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .accessibilityLabel(Text("Reduzir luz azul"))
        }
    }

    private var footer: some View {
        HStack {
            Button("Abrir LiteDisplay…", systemImage: "macwindow") { showMainWindow() }
                .buttonStyle(.pill)
            Spacer()
            Button("Sair", systemImage: "power") { NSApp.terminate(nil) }
                .buttonStyle(.pill(.secondary))
                .keyboardShortcut("q")
        }
    }

    private func showMainWindow() {
        openWindow(id: WindowID.main)
        NSApp.activate()
    }
}

private struct MenuDisplayRow: View {
    @Environment(AppContainer.self) private var container
    let display: DisplaySnapshot

    private var isSharp: Bool {
        display.activeMethod != .standard
    }

    private var canBeSharp: Bool {
        display.hasUsableHiDPI || container.monitors.isVirtualDisplayAvailable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Circle()
                    .fill(DesignTokens.color(for: display.activeMethod))
                    .frame(width: 8, height: 8)
                Text(display.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                sharpToggle
            }
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(display.currentMode?.summary ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if display.activeMethod == .hiDPI {
                    sizeMenu
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    private var sharpToggle: some View {
        Toggle("Texto nítido", isOn: Binding(
            get: { isSharp },
            set: { sharp in Task { await container.monitors.setSharp(sharp, for: display) } }
        ))
        .toggleStyle(.switch)
        .controlSize(.small)
        .labelsHidden()
        .disabled(container.monitors.isApplying || !canBeSharp)
        .accessibilityLabel(Text("Texto nítido em \(display.name)"))
    }

    private var sizeMenu: some View {
        Menu {
            ForEach(container.monitors.curatedSizes(for: display)) { entry in
                Button("\(entry.tier.title) · \(entry.size.description)") {
                    Task { await container.monitors.setSize(entry.size, for: display) }
                }
            }
        } label: {
            Label("Tamanho", systemImage: "rectangle.inset.filled")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
