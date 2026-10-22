// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// How LiteDisplay makes text sharp on a display.
enum SharpnessMethod: String, Codable, Sendable, CaseIterable, Identifiable {
    /// The panel's native 1x mode: macOS renders at 1:1 without HiDPI smoothing.
    case standard
    /// A HiDPI ("looks like") mode offered by the display or by an installed override: rendered at 2x and scaled to the panel.
    case hiDPI
    /// A virtual 2x display mirrored onto the panel: rendered at exactly 2x and downsampled 2:1.
    case virtualDisplay

    var id: String {
        rawValue
    }
}
