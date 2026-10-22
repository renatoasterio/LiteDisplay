// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
import Foundation

/// Reads mode tables from the window server. HiDPI modes only show up with the "duplicate low resolution" option.
@MainActor
enum DisplayModeCatalog {
    private static let stretchedFlag: UInt32 = 0x0000_0800
    private static let interlacedFlag: UInt32 = 0x0000_0040

    static func cgModes(for displayID: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        return (CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]) ?? []
    }

    /// Desktop-usable modes mapped to the domain type, deduplicated by geometry and rate.
    static func usableModes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        let modes = cgModes(for: displayID)
            .filter { $0.isUsableForDesktopGUI() && $0.ioFlags & (stretchedFlag | interlacedFlag) == 0 }
            .map(\.domainMode)
        var byKey: [ModeKey: DisplayMode] = [:]
        for mode in modes {
            if let existing = byKey[mode.key], (existing.ioFlags, -existing.id) >= (mode.ioFlags, -mode.id) {
                continue
            }
            byKey[mode.key] = mode
        }
        return byKey.values.sorted { ($0.width, $0.height, $0.isHiDPI ? 1 : 0, $0.refreshRate) > (
            $1.width,
            $1.height,
            $1.isHiDPI ? 1 : 0,
            $1.refreshRate
        ) }
    }

    static func currentMode(of displayID: CGDirectDisplayID) -> DisplayMode? {
        CGDisplayCopyDisplayMode(displayID)?.domainMode
    }

    /// The live CoreGraphics mode for a domain mode: by IOKit id first, by geometry when the table was re-read.
    static func cgMode(matching mode: DisplayMode, on displayID: CGDirectDisplayID) -> CGDisplayMode? {
        let all = cgModes(for: displayID)
        return all.first { $0.ioDisplayModeID == mode.id } ?? all.first { $0.domainMode.key == mode.key }
    }
}
