// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
import Foundation

/// Turns window-server reconfiguration callbacks into an `AsyncStream`. Registers once; unregisters in `deinit`.
final class DisplayReconfigurationObserver: Sendable {
    let changes: AsyncStream<DisplayChange>
    private let continuation: AsyncStream<DisplayChange>.Continuation

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: DisplayChange.self, bufferingPolicy: .unbounded)
        changes = stream
        self.continuation = continuation
        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
        continuation.finish()
    }

    func handle(_ displayID: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags) {
        // The "begin" phase carries no information; the matching completion phase follows immediately.
        guard !flags.contains(.beginConfigurationFlag) else { return }
        if flags.contains(.addFlag) {
            continuation.yield(.added(displayID))
        } else if flags.contains(.removeFlag) {
            continuation.yield(.removed(displayID))
        } else {
            continuation.yield(.reconfigured(displayID))
        }
    }
}

/// Top-level function so it converts to the C callback type without captures.
private func displayReconfigurationCallback(
    _ displayID: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo else { return }
    Unmanaged<DisplayReconfigurationObserver>.fromOpaque(userInfo).takeUnretainedValue().handle(displayID, flags)
}
