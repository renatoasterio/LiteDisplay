// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import Observation

/// Profiles persisted as one JSON file in Application Support, written atomically.
@MainActor
@Observable
final class ProfileStore: ProfileStoring {
    private(set) var profiles: [Profile] = []

    @ObservationIgnored private let fileURL: URL

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("profiles.json")
        profiles = Self.load(from: fileURL)
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("LiteDisplay", isDirectory: true)
    }

    func upsert(_ profile: Profile) throws(LiteDisplayError) {
        guard profile.isValid else { throw .storageFailed(String(localized: "perfil inválido")) }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        profiles.sort { $0.createdAt < $1.createdAt }
        try persist()
    }

    func delete(id: UUID) throws(LiteDisplayError) {
        profiles.removeAll { $0.id == id }
        try persist()
    }

    private static func load(from url: URL) -> [Profile] {
        guard let data = FileManager.default.contents(atPath: url.path) else { return [] }
        do {
            return try JSONDecoder().decode([Profile].self, from: data).filter(\.isValid)
        } catch {
            Log.storage.error("Profiles unreadable: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func persist() throws(LiteDisplayError) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(profiles).write(to: fileURL, options: [.atomic])
        } catch {
            Log.storage.error("Profiles not saved: \(error.localizedDescription, privacy: .public)")
            throw .storageFailed(error.localizedDescription)
        }
    }
}
