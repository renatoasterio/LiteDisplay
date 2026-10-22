// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// Everything about one display: hero, sharpness method, size, refresh rate, override and the full mode table.
struct MonitorDetailView: View {
    @Environment(AppContainer.self) private var container
    let display: DisplaySnapshot

    private var monitors: MonitorsViewModel {
        container.monitors
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                MonitorHero(display: display)
                if let error = monitors.error {
                    ErrorBanner(error: error) { monitors.dismissMessages() }
                    if error == .virtualDisplayLingering {
                        Button("Reabrir o LiteDisplay") { container.relaunch() }
                            .buttonStyle(.pill(.statusError))
                    }
                }
                if let notice = monitors.notice {
                    NoticeBanner(text: notice) { monitors.dismissMessages() }
                }
                SharpnessSection(display: display)
                if display.activeMethod == .virtualDisplay {
                    VirtualDisplayInfoCard(display: display)
                } else {
                    ResolutionSection(display: display)
                    RefreshRateSection(display: display)
                }
                if !display.hasUsableHiDPI {
                    OverrideCard(display: display)
                }
                AdvancedSection(display: display)
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .disabled(monitors.isApplying)
        .overlay(alignment: .top) {
            if monitors.isApplying {
                ProgressView("Aplicando…")
                    .padding(DesignTokens.Spacing.md)
                    .glassSurface(in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
                    .padding(.top, DesignTokens.Spacing.lg)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: monitors.isApplying)
    }
}

// MARK: - Hero

private struct MonitorHero: View {
    let display: DisplaySnapshot

    var body: some View {
        GradientHero(title: display.name, subtitle: subtitle) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                StatusBadge(method: display.activeMethod, onLight: true)
                if let mode = display.currentMode {
                    Chip(text: mode.size.description, systemImage: "rectangle.inset.filled", onLight: true)
                    Chip(text: mode.refreshRate.hertzLabel, systemImage: "gauge.with.needle", onLight: true)
                    Chip(text: mode.isHiDPI ? "2x" : "1x", systemImage: "magnifyingglass", onLight: true)
                }
                if display.isMain {
                    Chip(text: String(localized: "Principal"), systemImage: "star.fill", onLight: true)
                }
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let native = display.nativeSize {
            parts.append(String(localized: "Painel \(native.description)"))
        }
        if let mode = display.currentMode {
            parts.append(String(localized: "desenhando \(mode.pixelSize.description) px"))
        }
        if display.physicalSize.isKnown {
            let inches = (display.physicalSize.widthMM * display.physicalSize.widthMM + display.physicalSize.heightMM * display.physicalSize
                .heightMM).squareRoot() / 25.4
            parts.append(String(localized: "\(Int(inches.rounded()))″"))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Sharpness

private struct SharpnessSection: View {
    @Environment(AppContainer.self) private var container
    let display: DisplaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            SectionHeader(
                title: String(localized: "Nitidez"),
                subtitle: String(localized: "Como o macOS desenha neste monitor."),
                systemImage: "sparkles"
            )
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                ForEach(availableMethods) { method in
                    MethodCard(method: method, isSelected: display.activeMethod == method, isEnabled: isEnabled(method)) {
                        Task { await container.monitors.setMethod(method, for: display) }
                    }
                }
            }
        }
    }

    private var availableMethods: [SharpnessMethod] {
        SharpnessMethod.allCases.filter { $0 != .virtualDisplay || container.monitors.isVirtualDisplayAvailable }
    }

    private func isEnabled(_ method: SharpnessMethod) -> Bool {
        method != .hiDPI || display.hasUsableHiDPI
    }
}

private struct MethodCard: View {
    let method: SharpnessMethod
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                HStack {
                    Image(systemName: method.symbolName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(DesignTokens.color(for: method))
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DesignTokens.brandGradient)
                            .font(.title3)
                    }
                }
                Text(method.title)
                    .font(.headline)
                Text(isEnabled ? method.summary : String(localized: "Instale o perfil HiDPI abaixo para liberar este modo."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding(DesignTokens.Spacing.lg)
            .glassSurface(
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous),
                tint: isSelected ? DesignTokens.color(for: method) : nil
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                        .strokeBorder(DesignTokens.brandGradient, lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityLabel(Text(method.title))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Resolution

private struct ResolutionSection: View {
    @Environment(AppContainer.self) private var container
    let display: DisplaySnapshot

    var body: some View {
        let sizes = container.monitors.curatedSizes(for: display)
        if display.activeMethod == .hiDPI, !sizes.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                SectionHeader(
                    title: String(localized: "Tamanho da interface"),
                    subtitle: String(localized: "Tamanhos HiDPI: tudo continua nítido, muda só o espaço na tela."),
                    systemImage: "rectangle.inset.filled"
                )
                ResolutionGrid(sizes: sizes, selected: display.currentMode?.size) { size in
                    Task { await container.monitors.setSize(size, for: display) }
                }
            }
        } else if display.activeMethod == .standard {
            Card {
                HStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.statusLowRes)
                    Text("No modo padrão o monitor usa a resolução nativa. Escolha HiDPI nativo ou Tela virtual para texto nítido.")
                        .font(.callout)
                }
            }
        }
    }
}

// MARK: - Refresh rate

private struct RefreshRateSection: View {
    @Environment(AppContainer.self) private var container
    let display: DisplaySnapshot

    var body: some View {
        let rates = container.monitors.refreshRates(for: display)
        if rates.count > 1, let current = display.currentMode {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                SectionHeader(
                    title: String(localized: "Taxa de atualização"),
                    subtitle: String(localized: "Disponível para o tamanho atual."),
                    systemImage: "gauge.with.needle"
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        ForEach(rates, id: \.self) { rate in
                            SelectableChip(title: rate.hertzLabel, isSelected: current.matchesRefreshRate(rate)) {
                                Task { await container.monitors.setRefreshRate(rate, for: display) }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Virtual display info

private struct VirtualDisplayInfoCard: View {
    let display: DisplaySnapshot

    private var description: String {
        let backing = display.nativeSize?.doubled.description ?? "2x"
        let first = String(localized: "O monitor espelha uma tela virtual \(backing) desenhada em 2x.")
        let second = String(localized: "Tamanho e taxa ficam fixos enquanto ela estiver ligada; o espelhamento é desfeito ao sair do app.")
        return "\(first) \(second)"
    }

    var body: some View {
        Card(tint: .statusVirtual) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.title2)
                    .foregroundStyle(Color.statusVirtual)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Tela virtual ativa")
                        .font(.headline)
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Override

private struct OverrideCard: View {
    @Environment(AppContainer.self) private var container
    let display: DisplaySnapshot

    private var explanation: String {
        let largest = display.nativeSize.map { "\($0.width - 16)×\($0.height - 9)" } ?? "2x"
        let problem = String(localized: "O macOS não oferece modos HiDPI para este painel.")
        let solution =
            String(localized: "O LiteDisplay pode instalar um perfil em /Library/Displays com resoluções HiDPI de \(largest) para baixo.")
        let requirement = String(localized: "Mantém a taxa de atualização. Pede a senha de administrador e reconectar o monitor.")
        return "\(problem) \(solution) \(requirement)"
    }

    var body: some View {
        Card(tint: .brandCyan) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "wand.and.stars")
                        .font(.title2)
                        .foregroundStyle(DesignTokens.brandGradient)
                    Text("HiDPI indisponível neste monitor")
                        .font(.headline)
                }
                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if container.monitors.isOverridePending(for: display) {
                    Label("Perfil instalado. Desconecte e reconecte o monitor.", systemImage: "cable.connector")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.statusHiDPI)
                } else {
                    Button("Habilitar HiDPI neste monitor…") {
                        Task { await container.monitors.installOverride(for: display) }
                    }
                    .buttonStyle(.vibrant)
                }
            }
        }
    }
}

// MARK: - Advanced

private struct AdvancedSection: View {
    @Environment(AppContainer.self) private var container
    let display: DisplaySnapshot
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ModeTableView(display: display) { mode in
                Task { await container.monitors.apply(mode, to: display) }
            }
            .padding(.top, DesignTokens.Spacing.sm)
        } label: {
            SectionHeader(
                title: String(localized: "Todos os modos"),
                subtitle: String(localized: "\(display.modes.count) modos utilizáveis reportados pelo macOS."),
                systemImage: "list.bullet.rectangle"
            )
        }
        .disabled(display.activeMethod == .virtualDisplay)
    }
}
