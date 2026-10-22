// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Creates a 2x virtual display and mirrors a physical display onto it.
@MainActor
protocol VirtualDisplayControlling: AnyObject {
    /// False when the private API is missing from this macOS.
    var isAvailable: Bool { get }
    /// Display ids of the virtual displays currently owned by the app.
    var ownedDisplayIDs: Set<UInt32> { get }
    func isActive(for displayID: UInt32) -> Bool
    func activate(for display: DisplaySnapshot) async throws(LiteDisplayError)
    func deactivate(for displayID: UInt32) async throws(LiteDisplayError)
    func deactivateAll() async
    /// Unmirrors and drops every virtual display without waiting for the window server; for process termination,
    /// which must stay synchronous (an async reply from the main actor deadlocks inside `NSApplication.terminate`).
    func releaseAll()
}
