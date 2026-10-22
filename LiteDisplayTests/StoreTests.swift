// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import Testing
@testable import LiteDisplay

@Suite("Stores")
@MainActor
struct StoreTests {
    @Test("Profiles persist atomically and reload")
    func profileStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LiteDisplayTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory)
        let profile = Profile(
            name: "Jogos",
            displays: ["id": DisplaySettings(method: .standard, size: DisplaySize(width: 1920, height: 1080), refreshRate: 240)]
        )
        try store.upsert(profile)
        #expect(ProfileStore(directory: directory).profiles == [profile])
        try store.delete(id: profile.id)
        #expect(ProfileStore(directory: directory).profiles.isEmpty)
        #expect(throws: LiteDisplayError.self) { try store.upsert(Profile(name: "", displays: [:])) }
    }

    @Test("Settings persist in UserDefaults")
    func settingsStore() throws {
        let suite = "LiteDisplayTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        store.settings.reapplyOnConnect = false
        store.settings.displays["x"] = DisplaySettings(method: .hiDPI, size: DisplaySize(width: 1904, height: 1071), refreshRate: 120)
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.settings == store.settings)
    }
}
