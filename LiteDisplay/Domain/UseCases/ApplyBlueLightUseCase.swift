// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Applies or clears the blue light filter according to the settings, the schedule and the connected displays.
@MainActor
struct ApplyBlueLightUseCase {
    let displays: any DisplayProviding
    let virtualDisplays: any VirtualDisplayControlling
    let colorTemperature: any ColorTemperatureControlling
    let settings: any SettingsStoring

    /// Returns true when the filter is on screen after the call.
    @discardableResult
    func execute(now: Date = Date()) throws(LiteDisplayError) -> Bool {
        let blueLight = settings.settings.blueLight
        guard blueLight.shouldApply(at: now) else {
            colorTemperature.restore()
            return false
        }
        let gains = ColorTemperature.gains(kelvin: blueLight.kelvin)
        switch blueLight.scope {
        case .allDisplays:
            try colorTemperature.apply(gains, to: .allOnline)
        case .externalDisplays:
            // A mirrored panel shows its virtual source, so the source gets the gains too.
            let ids = Set(displays.externalDisplays().map(\.id)).union(virtualDisplays.ownedDisplayIDs)
            guard !ids.isEmpty else {
                colorTemperature.restore()
                return false
            }
            try colorTemperature.apply(gains, to: .displays(ids))
        }
        return true
    }
}
