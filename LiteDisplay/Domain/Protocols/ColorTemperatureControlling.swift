// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Which displays receive the gains.
enum ColorTemperatureTarget: Hashable, Sendable {
    case displays(Set<UInt32>)
    case allOnline
}

/// Warms or restores the white point of displays through their gamma tables.
@MainActor
protocol ColorTemperatureControlling: AnyObject {
    /// Applies gains on top of each display's own calibration; idempotent.
    func apply(_ gains: ChannelGains, to target: ColorTemperatureTarget) throws(LiteDisplayError)
    /// Restores every display's calibration.
    func restore()
}
