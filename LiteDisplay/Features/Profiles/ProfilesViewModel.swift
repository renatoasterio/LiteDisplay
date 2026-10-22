// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import Observation

/// Saved profiles and the actions on them.
@MainActor
@Observable
final class ProfilesViewModel {
    private(set) var profiles: [Profile] = []
    private(set) var isApplying = false
    var error: LiteDisplayError?
    var notice: String?

    @ObservationIgnored private let store: any ProfileStoring
    @ObservationIgnored private let saveProfile: SaveProfileUseCase
    @ObservationIgnored private let applyProfile: ApplyProfileUseCase
    /// Called after a profile changed the displays so the monitor screens refresh.
    @ObservationIgnored var displaysDidChange: (@MainActor () -> Void)?

    init(store: any ProfileStoring, saveProfile: SaveProfileUseCase, applyProfile: ApplyProfileUseCase) {
        self.store = store
        self.saveProfile = saveProfile
        self.applyProfile = applyProfile
    }

    func reload() {
        profiles = store.profiles
    }

    func saveCurrent(name: String, color: ProfileColor, symbolName: String, applyOnConnect: Bool) {
        do {
            let profile = try saveProfile.execute(name: name, color: color, symbolName: symbolName, applyOnConnect: applyOnConnect)
            notice = String(localized: "Perfil “\(profile.name)” salvo.")
            error = nil
        } catch {
            self.error = error
        }
        reload()
    }

    func update(_ profile: Profile) {
        do {
            try store.upsert(profile)
            error = nil
        } catch {
            self.error = error
        }
        reload()
    }

    func delete(_ profile: Profile) {
        do {
            try store.delete(id: profile.id)
            error = nil
        } catch {
            self.error = error
        }
        reload()
    }

    func apply(_ profile: Profile) async {
        guard !isApplying else { return }
        isApplying = true
        error = nil
        notice = nil
        defer { isApplying = false }
        do {
            let count = try await applyProfile.execute(profile)
            notice = count == 0
                ? String(localized: "“\(profile.name)” já estava aplicado.")
                : String(localized: "“\(profile.name)” aplicado.")
        } catch {
            self.error = error
            Log.ui.error("Profile apply failed: \(error.localizedDescription, privacy: .public)")
        }
        displaysDidChange?()
    }

    func dismissMessages() {
        error = nil
        notice = nil
    }
}
