// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import Observation

/// Blue light filter state: mirrors the persisted settings, applies changes live and follows the schedule.
@MainActor
@Observable
final class ComfortViewModel {
    private static let scheduleTick: Duration = .seconds(60)
    private static let sliderDebounce: Duration = .milliseconds(120)

    var isEnabled: Bool {
        didSet {
            if isEnabled != oldValue {
                persist()
            }
        }
    }

    /// Slider value in kelvin; applied with a short debounce so dragging previews live without flooding the window server.
    var kelvin: Double {
        didSet {
            if kelvin != oldValue {
                persistDebounced()
            }
        }
    }

    var scope: BlueLightScope {
        didSet {
            if scope != oldValue {
                persist()
            }
        }
    }

    var usesSchedule: Bool {
        didSet {
            if usesSchedule != oldValue {
                persist()
            }
        }
    }

    var scheduleStart: TimeOfDay {
        didSet {
            if scheduleStart != oldValue {
                persist()
            }
        }
    }

    var scheduleEnd: TimeOfDay {
        didSet {
            if scheduleEnd != oldValue {
                persist()
            }
        }
    }

    private(set) var isActiveNow = false
    var error: LiteDisplayError?

    @ObservationIgnored private let settings: any SettingsStoring
    @ObservationIgnored private let applyFilter: ApplyBlueLightUseCase
    @ObservationIgnored private var scheduler: Task<Void, Never>?
    @ObservationIgnored private var pendingApply: Task<Void, Never>?

    init(settings: any SettingsStoring, applyFilter: ApplyBlueLightUseCase) {
        self.settings = settings
        self.applyFilter = applyFilter
        let stored = settings.settings.blueLight.sanitized
        isEnabled = stored.isEnabled
        kelvin = Double(stored.kelvin)
        scope = stored.scope
        switch stored.schedule {
        case .always:
            usesSchedule = false
            if case let .daily(start, end) = BlueLightSchedule.defaultDaily {
                scheduleStart = start
                scheduleEnd = end
            } else {
                scheduleStart = TimeOfDay(hour: 18, minute: 0)
                scheduleEnd = TimeOfDay(hour: 7, minute: 0)
            }
        case let .daily(start, end):
            usesSchedule = true
            scheduleStart = start
            scheduleEnd = end
        }
    }

    var kelvinLabel: String {
        "\(Int(kelvin.rounded())) K"
    }

    func start() {
        reapply()
        scheduler?.cancel()
        scheduler = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.scheduleTick)
                guard let self, !Task.isCancelled else { return }
                reapply()
            }
        }
    }

    func stop() {
        scheduler?.cancel()
        scheduler = nil
        pendingApply?.cancel()
        pendingApply = nil
    }

    /// Re-applies the current settings; cheap, so it also runs after every display change and after wake.
    func reapply() {
        do {
            isActiveNow = try applyFilter.execute()
            error = nil
        } catch {
            self.error = error
            Log.ui.error("Blue light filter failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func toggle() {
        isEnabled.toggle()
    }

    private var currentSettings: BlueLightSettings {
        BlueLightSettings(
            isEnabled: isEnabled,
            kelvin: Int(kelvin.rounded()),
            scope: scope,
            schedule: usesSchedule ? .daily(start: scheduleStart, end: scheduleEnd) : .always
        ).sanitized
    }

    private func persist() {
        pendingApply?.cancel()
        settings.settings.blueLight = currentSettings
        reapply()
    }

    private func persistDebounced() {
        pendingApply?.cancel()
        pendingApply = Task { [weak self] in
            try? await Task.sleep(for: Self.sliderDebounce)
            guard let self, !Task.isCancelled else { return }
            persist()
        }
    }
}
