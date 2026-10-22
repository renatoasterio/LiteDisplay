// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Physical dimensions reported by the display's EDID.
struct PhysicalSize: Hashable, Sendable {
    let widthMM: Double
    let heightMM: Double

    var isKnown: Bool {
        widthMM > 0 && heightMM > 0
    }

    /// Points per inch of a mode on this panel, or nil when the size is unknown.
    func pointsPerInch(for mode: DisplayMode) -> Double? {
        guard isKnown else { return nil }
        return Double(mode.width) / (widthMM / 25.4)
    }
}

/// An immutable view of one connected display and its mode table.
struct DisplaySnapshot: Identifiable, Hashable, Sendable {
    /// Minimum point density for a HiDPI mode to count as usable (Apple's stock half-resolution mode on a 1080p panel is ~40 ppi).
    static let minimumUsablePointsPerInch = 60.0
    /// Vendor id LiteDisplay stamps on its virtual displays ("LD").
    static let virtualDisplayVendorID: UInt32 = 0x4C44

    /// CoreGraphics display id for this connection.
    let id: UInt32
    /// Stable id across reconnections (EDID UUID or vendor-product-serial).
    let persistentID: String
    let name: String
    let vendorID: UInt32
    let productID: UInt32
    let serialNumber: UInt32
    let physicalSize: PhysicalSize
    let isMain: Bool
    let isBuiltIn: Bool
    /// The display whose image this one shows, when it is part of a mirror set.
    let mirrorSourceID: UInt32?
    /// True when the mirrored source is a virtual display owned by LiteDisplay.
    let isMirroringVirtualDisplay: Bool
    let currentMode: DisplayMode?
    /// Usable desktop modes, deduplicated.
    let modes: [DisplayMode]

    var vendorHex: String {
        String(vendorID, radix: 16)
    }

    var productHex: String {
        String(productID, radix: 16)
    }

    var nativeMode: DisplayMode? {
        ModeSelection.nativeMode(in: modes, preferredRate: currentMode?.refreshRate)
    }

    var nativeSize: DisplaySize? {
        nativeMode?.size
    }

    /// True when at least one HiDPI mode is sharp and large enough to work on (not Apple's stock half-resolution mode).
    var hasUsableHiDPI: Bool {
        modes.contains { mode in
            guard mode.isHiDPI else { return false }
            if let ppi = physicalSize.pointsPerInch(for: mode) {
                return ppi >= Self.minimumUsablePointsPerInch
            }
            guard let native = nativeSize else { return false }
            return mode.width * 2 > native.width
        }
    }

    var activeMethod: SharpnessMethod {
        if isMirroringVirtualDisplay {
            return .virtualDisplay
        }
        return currentMode?.isHiDPI == true ? .hiDPI : .standard
    }

    /// The configuration currently on screen, as something that can be stored and re-applied.
    var currentSettings: DisplaySettings {
        switch activeMethod {
        case .virtualDisplay:
            DisplaySettings(method: .virtualDisplay, size: nativeSize, refreshRate: currentMode?.refreshRate)
        case .standard, .hiDPI:
            DisplaySettings(method: activeMethod, size: currentMode?.size, refreshRate: currentMode?.refreshRate)
        }
    }
}
