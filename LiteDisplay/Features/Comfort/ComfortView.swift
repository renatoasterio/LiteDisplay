// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// Blue light filter: on/off, warmth, which displays, and an optional daily schedule.
struct ComfortView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                ComfortHero(comfort: container.comfort)
                if let error = container.comfort.error {
                    ErrorBanner(error: error) { container.comfort.error = nil }
                }
                EnableCard(comfort: container.comfort)
                SectionHeader(
                    title: String(localized: "Intensidade"),
                    subtitle: String(localized: "Temperatura de cor do branco."),
                    systemImage: "thermometer.medium"
                )
                WarmthCard(comfort: container.comfort)
                SectionHeader(title: String(localized: "Telas"), systemImage: "display.2")
                ScopeCard(comfort: container.comfort)
                SectionHeader(
                    title: String(localized: "Horário"),
                    subtitle: String(localized: "Deixe desligado para valer o dia todo."),
                    systemImage: "clock"
                )
                ScheduleCard(comfort: container.comfort)
                InfoCard()
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ComfortHero: View {
    let comfort: ComfortViewModel

    var body: some View {
        GradientHero(
            title: String(localized: "Conforto visual"),
            subtitle: String(localized: "Menos luz azul à noite ou o dia todo, sem mexer no brilho.")
        ) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Chip(
                    text: comfort.isActiveNow ? String(localized: "Ativo agora") : String(localized: "Inativo"),
                    systemImage: comfort.isActiveNow ? "sun.haze.fill" : "sun.max",
                    onLight: true
                )
                if comfort.isEnabled {
                    Chip(text: comfort.kelvinLabel, systemImage: "thermometer.medium", onLight: true)
                }
            }
        }
    }
}

private struct EnableCard: View {
    @Bindable var comfort: ComfortViewModel

    var body: some View {
        Card(tint: comfort.isEnabled ? .statusLowRes : nil) {
            Toggle(isOn: $comfort.isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reduzir luz azul")
                        .font(.headline)
                    Text("Aquece o branco da tela ajustando a curva de cor do monitor. Vale enquanto o LiteDisplay estiver aberto.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }
}

private struct WarmthCard: View {
    @Bindable var comfort: ComfortViewModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                HStack {
                    Text(comfort.kelvinLabel)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Spacer()
                    Text(warmthDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $comfort.kelvin,
                    in: Double(BlueLightSettings.minimumKelvin) ... Double(BlueLightSettings.maximumKelvin),
                    step: 100
                ) {
                    Text("Intensidade")
                } minimumValueLabel: {
                    Image(systemName: "sun.haze.fill")
                        .foregroundStyle(Color.statusLowRes)
                } maximumValueLabel: {
                    Image(systemName: "sun.max")
                        .foregroundStyle(Color.brandCyan)
                }
                .disabled(!comfort.isEnabled)
                HStack {
                    Text("Mais quente")
                    Spacer()
                    Text("Neutro")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var warmthDescription: String {
        switch comfort.kelvin {
        case ..<3400: String(localized: "Forte, para a noite")
        case ..<4600: String(localized: "Médio, confortável para longas sessões")
        case ..<5800: String(localized: "Suave")
        default: String(localized: "Quase neutro")
        }
    }
}

private struct ScopeCard: View {
    @Bindable var comfort: ComfortViewModel

    var body: some View {
        Card {
            Picker("Aplicar em", selection: $comfort.scope) {
                Text("Só monitores externos").tag(BlueLightScope.externalDisplays)
                Text("Todas as telas").tag(BlueLightScope.allDisplays)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

private struct ScheduleCard: View {
    @Bindable var comfort: ComfortViewModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                Toggle("Só em um horário", isOn: $comfort.usesSchedule)
                    .toggleStyle(.switch)
                if comfort.usesSchedule {
                    HStack(spacing: DesignTokens.Spacing.lg) {
                        TimeField(title: String(localized: "Das"), time: $comfort.scheduleStart)
                        TimeField(title: String(localized: "Até"), time: $comfort.scheduleEnd)
                        Spacer()
                    }
                    Text("O intervalo pode atravessar a meia-noite, como 18:00 até 07:00.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct InfoCard: View {
    var body: some View {
        Card {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.brandCyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("O ajuste é desfeito ao sair do app e refeito ao reconectar o monitor ou acordar o Mac.")
                    Text("Para valer sempre, ative “Iniciar no login” em Ajustes.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// Hour and minute picker backed by `TimeOfDay`.
private struct TimeField: View {
    let title: String
    @Binding var time: TimeOfDay

    var body: some View {
        DatePicker(title, selection: dateBinding, displayedComponents: .hourAndMinute)
            .datePickerStyle(.stepperField)
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date() },
            set: { time = TimeOfDay.of($0) }
        )
    }
}
