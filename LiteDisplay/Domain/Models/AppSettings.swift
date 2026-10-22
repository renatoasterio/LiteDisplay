// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// App-wide preferences and the last configuration applied to each display.
struct AppSettings: Codable, Sendable, Hashable {
    var reapplyOnConnect = true
    var showsWindowAtLaunch = true
    /// Persistent display id → last applied configuration.
    var displays: [String: DisplaySettings] = [:]
}
