// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
@testable import LiteDisplay

/// Mode tables shaped like real displays.
enum Fixtures {
    static let rates: [Double] = [240, 144, 120, 60, 50, 30]
    static let fullHDPhysical = PhysicalSize(widthMM: 602, heightMM: 338)

    /// A 1080p panel with the one-key-hidpi override installed (the XB273 GX on this Mac).
    static func fullHDModes() -> [DisplayMode] {
        var builder = ModeBuilder()
        for rate in rates {
            builder.add(1920, 1080, scale: 1, rate: rate, flags: DisplayMode.nativeFlag | (rate == 240 ? DisplayMode.defaultFlag : 0))
        }
        for width in stride(from: 1904, through: 1280, by: -16) {
            let height = Int((Double(width) * 1080 / 1920).rounded())
            for rate in rates {
                builder.add(width, height, scale: 1, rate: rate)
                builder.add(width, height, scale: 2, rate: rate)
            }
        }
        builder.add(960, 540, scale: 2, rate: 60, flags: DisplayMode.nativeFlag)
        return builder.modes
    }

    /// The same panel without the override: 1x modes and Apple's stock half-resolution mode only.
    static func fullHDModesWithoutOverride() -> [DisplayMode] {
        var builder = ModeBuilder()
        for rate in rates {
            builder.add(1920, 1080, scale: 1, rate: rate, flags: DisplayMode.nativeFlag)
            builder.add(1600, 900, scale: 1, rate: rate)
            builder.add(1280, 720, scale: 1, rate: rate)
        }
        builder.add(960, 540, scale: 2, rate: 60, flags: DisplayMode.nativeFlag)
        return builder.modes
    }

    /// A 27" 4K panel with Apple's own HiDPI ladder.
    static func fourKModes() -> [DisplayMode] {
        var builder = ModeBuilder()
        builder.add(3840, 2160, scale: 1, rate: 60, flags: DisplayMode.nativeFlag | DisplayMode.defaultFlag)
        for (width, height) in [(3008, 1692), (2560, 1440), (1920, 1080), (1600, 900), (1440, 810), (1280, 720)] {
            builder.add(width, height, scale: 2, rate: 60)
        }
        return builder.modes
    }

    static func mode(in modes: [DisplayMode], _ width: Int, _ height: Int, scale: Int, rate: Double) -> DisplayMode {
        guard let mode = modes
            .first(where: { $0.width == width && $0.height == height && $0.scale == scale && $0.matchesRefreshRate(rate) }) else {
            fatalError("fixture mode \(width)x\(height)@\(scale)x \(rate)Hz missing")
        }
        return mode
    }

    static func display(
        id: UInt32 = 3,
        persistentID: String = "079D661E-8DFD-412E-8481-D20CE19C6CA4",
        name: String = "XB273 GX",
        modes: [DisplayMode],
        current: DisplayMode?,
        mirroringVirtual: Bool = false,
        physical: PhysicalSize = fullHDPhysical
    ) -> DisplaySnapshot {
        DisplaySnapshot(
            id: id,
            persistentID: persistentID,
            name: name,
            vendorID: 0x472,
            productID: 0x746,
            serialNumber: 270_608_687,
            physicalSize: physical,
            isMain: true,
            isBuiltIn: false,
            mirrorSourceID: mirroringVirtual ? id + 1000 : nil,
            isMirroringVirtualDisplay: mirroringVirtual,
            currentMode: current,
            modes: modes
        )
    }

    /// The XB273 GX as it is right now: 1920x1080 1x at 120 Hz.
    static func fullHDDisplay(current: DisplayMode? = nil) -> DisplaySnapshot {
        let modes = fullHDModes()
        return display(modes: modes, current: current ?? mode(in: modes, 1920, 1080, scale: 1, rate: 120))
    }

    struct ModeBuilder {
        private(set) var modes: [DisplayMode] = []
        private var nextID: Int32 = 100

        mutating func add(_ width: Int, _ height: Int, scale: Int, rate: Double, flags: UInt32 = 0x3) {
            modes.append(DisplayMode(
                id: nextID,
                width: width,
                height: height,
                pixelWidth: width * scale,
                pixelHeight: height * scale,
                refreshRate: rate,
                ioFlags: flags | 0x3
            ))
            nextID += 1
        }
    }
}
