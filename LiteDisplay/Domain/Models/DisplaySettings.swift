// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// What the user wants on one display. Stored per display (by persistent id) and inside profiles.
struct DisplaySettings: Codable, Sendable, Hashable {
    var method: SharpnessMethod = .standard
    /// "Looks like" size in points. `nil` means "the best for the method".
    var size: DisplaySize?
    /// `nil` means "keep the current refresh rate".
    var refreshRate: Double?

    init(method: SharpnessMethod = .standard, size: DisplaySize? = nil, refreshRate: Double? = nil) {
        self.method = method
        self.size = size
        self.refreshRate = refreshRate
    }

    /// True when a display already shows this configuration, so re-applying it would only flash the screen.
    func isSatisfied(by display: DisplaySnapshot) -> Bool {
        guard display.activeMethod == method else { return false }
        if method == .virtualDisplay {
            return true
        }
        guard let current = display.currentMode else { return false }
        if let size, size != current.size {
            return false
        }
        if let refreshRate, !current.matchesRefreshRate(refreshRate) {
            return false
        }
        return true
    }
}
