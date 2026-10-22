// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit

/// Runs handlers around system sleep. Selector-based observation keeps `deinit` free of isolated state:
/// it only unregisters `self`.
@MainActor
final class SleepWakeObserver: NSObject {
    private let onSleep: @MainActor @Sendable () -> Void
    private let onWake: @MainActor @Sendable () -> Void

    init(onSleep: @escaping @MainActor @Sendable () -> Void, onWake: @escaping @MainActor @Sendable () -> Void) {
        self.onSleep = onSleep
        self.onWake = onWake
        super.init()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func willSleep() {
        onSleep()
    }

    @objc private func didWake() {
        onWake()
    }
}
