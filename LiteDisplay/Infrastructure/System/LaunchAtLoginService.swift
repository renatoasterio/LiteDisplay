// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import ServiceManagement

/// Registers the app as a login item through `SMAppService`.
@MainActor
final class LaunchAtLoginService: LoginItemControlling {
    private let service = SMAppService.mainApp

    var isEnabled: Bool {
        service.status == .enabled
    }

    var requiresApproval: Bool {
        service.status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws(LiteDisplayError) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            Log.system.info("Login item \(enabled ? "registered" : "unregistered")")
        } catch {
            Log.system.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            throw .loginItemFailed(error.localizedDescription)
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
