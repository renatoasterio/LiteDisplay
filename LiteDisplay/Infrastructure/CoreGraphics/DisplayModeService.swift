// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
import Foundation

/// Switches modes inside a display configuration transaction committed permanently, so macOS restores the
/// choice on reconnect and after the app quits. `CGDisplaySetDisplayMode` is never used: it reverts at exit.
@MainActor
final class DisplayModeService: DisplayModeApplying {
    func currentMode(of displayID: UInt32) -> DisplayMode? {
        DisplayModeCatalog.currentMode(of: displayID)
    }

    func apply(_ mode: DisplayMode, to displayID: UInt32) throws(LiteDisplayError) {
        guard CGDisplayIsOnline(displayID) != 0 else { throw .displayNotFound }
        guard let cgMode = DisplayModeCatalog.cgMode(matching: mode, on: displayID) else { throw .modeUnavailable }

        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else { throw .configurationFailed(stage: "begin", code: begin.rawValue) }

        let configure = CGConfigureDisplayWithDisplayMode(config, displayID, cgMode, nil)
        guard configure == .success else {
            CGCancelDisplayConfiguration(config)
            throw .configurationFailed(stage: "configure", code: configure.rawValue)
        }

        // Complete releases the configuration whether or not it succeeds.
        let complete = CGCompleteDisplayConfiguration(config, .permanently)
        guard complete == .success else { throw .configurationFailed(stage: "complete", code: complete.rawValue) }

        guard let now = CGDisplayCopyDisplayMode(displayID), now.ioDisplayModeID == cgMode.ioDisplayModeID else {
            throw .verificationFailed
        }
        Log.display
            .info(
                "Display \(displayID) now \(mode.width)x\(mode.height)@\(mode.scale)x \(mode.refreshRate, format: .fixed(precision: 0)) Hz"
            )
    }
}
