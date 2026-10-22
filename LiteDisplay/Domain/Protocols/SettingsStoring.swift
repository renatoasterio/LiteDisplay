// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Persistent app settings.
@MainActor
protocol SettingsStoring: AnyObject {
    var settings: AppSettings { get set }
}
