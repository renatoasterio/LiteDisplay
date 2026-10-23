// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// What happened to the virtual display after a deactivation.
enum VirtualDisplayDeactivation: Sendable {
    case removed
    /// The window server keeps a virtual display that took part in a configuration until the process exits.
    case lingering
}

/// Creates a 2x virtual display and mirrors a physical display onto it.
@MainActor
protocol VirtualDisplayControlling: AnyObject {
    /// False when the private API is missing from this macOS.
    var isAvailable: Bool { get }
    /// Display ids of every virtual display the app created and that is still present, lingering ones included.
    var ownedDisplayIDs: Set<UInt32> { get }
    /// Virtual displays released by the app that only disappear when the process exits; the app relaunches to free them.
    var lingeringDisplayIDs: Set<UInt32> { get }
    func isActive(for displayID: UInt32) -> Bool
    func activate(for display: DisplaySnapshot) async throws(LiteDisplayError)
    /// Unmirrors the panel, gives it the main role back and drops the virtual display.
    @discardableResult
    func deactivate(for displayID: UInt32) async throws(LiteDisplayError) -> VirtualDisplayDeactivation
    func deactivateAll() async
    /// Unmirrors every panel but keeps the virtual displays, for system sleep.
    func suspendAll()
    /// Re-mirrors the panels suspended by `suspendAll()` onto their virtual displays.
    func resumeAll() throws(LiteDisplayError)
    /// Unmirrors and drops every virtual display without waiting for the window server; for process termination,
    /// which must stay synchronous (an async reply from the main actor deadlocks inside `NSApplication.terminate`).
    func releaseAll()
}
