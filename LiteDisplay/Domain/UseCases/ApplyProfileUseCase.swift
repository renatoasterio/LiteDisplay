// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Applies a profile to every connected display it covers. Returns how many displays changed.
@MainActor
struct ApplyProfileUseCase {
    let displays: any DisplayProviding
    let sharpness: SetSharpnessUseCase

    @discardableResult
    func execute(_ profile: Profile) async throws(LiteDisplayError) -> Int {
        var applied = 0
        for display in displays.externalDisplays() {
            guard let wanted = profile.displays[display.persistentID] else { continue }
            if wanted.isSatisfied(by: display) {
                continue
            }
            try await sharpness.execute(.init(display: display, method: wanted.method, size: wanted.size, refreshRate: wanted.refreshRate))
            applied += 1
        }
        return applied
    }
}
