// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Switches a display to a mode permanently (the window server remembers it across sessions).
@MainActor
protocol DisplayModeApplying: AnyObject {
    func apply(_ mode: DisplayMode, to displayID: UInt32) throws(LiteDisplayError)
    func currentMode(of displayID: UInt32) -> DisplayMode?
}
