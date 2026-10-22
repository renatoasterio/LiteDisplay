// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Generates and installs the HiDPI override for a display that offers no usable HiDPI mode.
@MainActor
struct EnableHiDPIOverrideUseCase {
    let installer: any OverrideInstalling

    func profile(for display: DisplaySnapshot) throws(LiteDisplayError) -> HiDPIOverrideProfile {
        guard let native = display.nativeSize else { throw .modeUnavailable }
        let profile = HiDPIOverrideProfile(vendorID: display.vendorID, productID: display.productID, nativeSize: native)
        guard profile.hasValidIdentifiers, !profile.entries.isEmpty else { throw .invalidIdentifier }
        return profile
    }

    func execute(for display: DisplaySnapshot) async throws(LiteDisplayError) -> HiDPIOverrideProfile {
        let profile = try profile(for: display)
        try await installer.install(profile)
        return profile
    }
}
