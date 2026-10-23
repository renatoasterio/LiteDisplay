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
    var blueLight = BlueLightSettings()

    private enum CodingKeys: String, CodingKey {
        case reapplyOnConnect, showsWindowAtLaunch, displays, blueLight
    }

    init() {}

    /// Settings written by an older version lack newer keys; every key is optional on read.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reapplyOnConnect = try container.decodeIfPresent(Bool.self, forKey: .reapplyOnConnect) ?? true
        showsWindowAtLaunch = try container.decodeIfPresent(Bool.self, forKey: .showsWindowAtLaunch) ?? true
        displays = try container.decodeIfPresent([String: DisplaySettings].self, forKey: .displays) ?? [:]
        blueLight = try (container.decodeIfPresent(BlueLightSettings.self, forKey: .blueLight) ?? BlueLightSettings()).sanitized
    }
}
