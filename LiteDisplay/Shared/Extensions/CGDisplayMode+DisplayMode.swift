// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics

extension CGDisplayMode {
    /// The framework-free value used everywhere above Infrastructure.
    var domainMode: DisplayMode {
        DisplayMode(
            id: ioDisplayModeID,
            width: width,
            height: height,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            refreshRate: refreshRate,
            ioFlags: ioFlags
        )
    }
}
