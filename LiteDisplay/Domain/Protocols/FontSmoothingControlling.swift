// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Global text smoothing preference (grayscale antialiasing weight on non-Retina displays).
@MainActor
protocol FontSmoothingControlling: AnyObject {
    func isStrongSmoothingEnabled() -> Bool
    func setStrongSmoothing(_ enabled: Bool) throws(LiteDisplayError)
}
