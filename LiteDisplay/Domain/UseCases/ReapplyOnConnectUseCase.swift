// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// When a display comes back, restores the profile marked "apply on connect" or the last configuration used on it.
@MainActor
struct ReapplyOnConnectUseCase {
    let displays: any DisplayProviding
    let profiles: any ProfileStoring
    let settings: any SettingsStoring
    let sharpness: SetSharpnessUseCase

    /// Returns true when something was applied.
    @discardableResult
    func execute(displayID: UInt32) async throws(LiteDisplayError) -> Bool {
        guard settings.settings.reapplyOnConnect,
              let display = displays.externalDisplays().first(where: { $0.id == displayID }) else { return false }
        let fromProfile = profiles.profiles.first { $0.applyOnConnect && $0.displays[display.persistentID] != nil }?
            .displays[display.persistentID]
        guard let wanted = fromProfile ?? settings.settings.displays[display.persistentID] else { return false }
        if wanted.isSatisfied(by: display) {
            return false
        }
        try await sharpness.execute(.init(display: display, method: wanted.method, size: wanted.size, refreshRate: wanted.refreshRate))
        return true
    }
}
