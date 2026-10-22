// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import Observation

/// App settings persisted as JSON in `UserDefaults`.
@MainActor
@Observable
final class SettingsStore: SettingsStoring {
    private static let key = "settings"

    @ObservationIgnored private let defaults: UserDefaults

    var settings: AppSettings {
        didSet {
            if settings != oldValue {
                persist()
            }
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        settings = Self.load(from: defaults)
    }

    private static func load(from defaults: UserDefaults) -> AppSettings {
        guard let data = defaults.data(forKey: key) else { return AppSettings() }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            Log.storage.error("Settings unreadable, using defaults: \(error.localizedDescription, privacy: .public)")
            return AppSettings()
        }
    }

    private func persist() {
        do {
            try defaults.set(JSONEncoder().encode(settings), forKey: Self.key)
        } catch {
            Log.storage.error("Settings not saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
