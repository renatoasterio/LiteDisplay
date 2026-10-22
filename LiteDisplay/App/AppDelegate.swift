// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container = AppContainer.live()

    func applicationDidFinishLaunching(_ notification: Notification) {
        container.start()
        Log.app.info("LiteDisplay launched")
        #if DEBUG
        if let request = DebugAutomation.request() {
            Task { await DebugAutomation.run(request, container: container) }
        }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The menu bar extra keeps the app useful without any window.
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Undo mirroring before the virtual displays vanish with the process. Synchronous: a `.terminateLater`
        // reply from a main-actor Task never runs when terminate was itself called from a main-actor Task.
        container.shutdown()
        return .terminateNow
    }
}
