// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

enum WindowID {
    static let main = "main"
}

@main
struct LiteDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("LiteDisplay", id: WindowID.main) {
            MainWindowView()
                .environment(appDelegate.container)
        }
        .defaultSize(width: DesignTokens.Window.width, height: DesignTokens.Window.height)
        .defaultLaunchBehavior(appDelegate.container.settings.settings.showsWindowAtLaunch ? .presented : .suppressed)
        .restorationBehavior(.disabled)

        MenuBarExtra {
            MenuBarMenuView()
                .environment(appDelegate.container)
        } label: {
            Image(systemName: "display")
                .accessibilityLabel("LiteDisplay")
        }
        .menuBarExtraStyle(.window)
    }
}
