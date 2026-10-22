// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// A size in points or pixels.
struct DisplaySize: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    let width: Int
    let height: Int

    var pixelCount: Int {
        width * height
    }

    var aspectRatio: Double {
        height > 0 ? Double(width) / Double(height) : 0
    }

    var description: String {
        "\(width)×\(height)"
    }

    /// Twice the size (the backing store of a HiDPI mode).
    var doubled: DisplaySize {
        DisplaySize(width: width * 2, height: height * 2)
    }

    static func < (lhs: DisplaySize, rhs: DisplaySize) -> Bool {
        lhs.pixelCount == rhs.pixelCount ? lhs.width < rhs.width : lhs.pixelCount < rhs.pixelCount
    }
}

/// Identity of a mode independent of the IOKit identifier (used when a mode list is re-read).
struct ModeKey: Hashable, Sendable {
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let centiHertz: Int
}

/// One display mode as reported by the window server, in points and backing pixels.
struct DisplayMode: Hashable, Sendable, Codable, Identifiable {
    /// kDisplayModeNativeFlag: the panel's own timing.
    static let nativeFlag: UInt32 = 0x0200_0000
    /// kDisplayModeDefaultFlag: what macOS picks for a fresh connection.
    static let defaultFlag: UInt32 = 0x0000_0004
    /// Two refresh rates closer than this are the same rate (drivers report 59.94 vs 60).
    static let refreshRateTolerance = 0.5

    /// IOKit identifier of the mode, unique per connection.
    let id: Int32
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let ioFlags: UInt32

    var size: DisplaySize {
        DisplaySize(width: width, height: height)
    }

    var pixelSize: DisplaySize {
        DisplaySize(width: pixelWidth, height: pixelHeight)
    }

    /// 2 for HiDPI ("looks like") modes, 1 otherwise.
    var scale: Int {
        width > 0 ? max(1, pixelWidth / width) : 1
    }

    var isHiDPI: Bool {
        pixelWidth >= width * 2
    }

    var isNative1x: Bool {
        ioFlags & Self.nativeFlag != 0 && !isHiDPI
    }

    var isDefault: Bool {
        ioFlags & Self.defaultFlag != 0
    }

    var key: ModeKey {
        ModeKey(
            width: width,
            height: height,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            centiHertz: Int((refreshRate * 100).rounded())
        )
    }

    func matchesRefreshRate(_ rate: Double) -> Bool {
        abs(refreshRate - rate) < Self.refreshRateTolerance
    }
}

extension Double {
    /// "120 Hz"
    var hertzLabel: String {
        "\(Int(rounded())) Hz"
    }
}
