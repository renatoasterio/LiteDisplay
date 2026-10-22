// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import OSLog

/// One logger per area. Display names and paths are logged with `privacy: .private`.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "br.com.asoft.LiteDisplay"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let display = Logger(subsystem: subsystem, category: "display")
    static let virtualDisplay = Logger(subsystem: subsystem, category: "virtual-display")
    static let override = Logger(subsystem: subsystem, category: "override")
    static let system = Logger(subsystem: subsystem, category: "system")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
