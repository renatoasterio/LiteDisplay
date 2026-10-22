// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Installs a HiDPI override into /Library/Displays with administrator rights.
protocol OverrideInstalling: Sendable {
    func isInstalled(_ profile: HiDPIOverrideProfile) -> Bool
    func install(_ profile: HiDPIOverrideProfile) async throws(LiteDisplayError)
}
