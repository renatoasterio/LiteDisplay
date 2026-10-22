// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// A change the window server reported for one display.
enum DisplayChange: Hashable, Sendable {
    case added(UInt32)
    case removed(UInt32)
    case reconfigured(UInt32)
}

/// Enumerates the external displays and streams their changes.
@MainActor
protocol DisplayProviding: AnyObject {
    /// External, non-virtual displays only.
    func externalDisplays() -> [DisplaySnapshot]
    /// One subscriber only: the stream is consumed by the monitors view model.
    var changes: AsyncStream<DisplayChange> { get }
}
