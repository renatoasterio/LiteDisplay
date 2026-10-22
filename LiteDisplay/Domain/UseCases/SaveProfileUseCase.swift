// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Captures what every connected display shows right now into a named profile.
@MainActor
struct SaveProfileUseCase {
    let displays: any DisplayProviding
    let profiles: any ProfileStoring

    @discardableResult
    func execute(name: String, color: ProfileColor, symbolName: String, applyOnConnect: Bool) throws(LiteDisplayError) -> Profile {
        let captured = displays.externalDisplays().reduce(into: [String: DisplaySettings]()) { result, display in
            result[display.persistentID] = display.currentSettings
        }
        let profile = Profile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            color: color,
            symbolName: symbolName,
            displays: captured,
            applyOnConnect: applyOnConnect
        )
        guard profile.isValid else { throw .storageFailed(String(localized: "dê um nome ao perfil e conecte um monitor")) }
        try profiles.upsert(profile)
        return profile
    }
}
