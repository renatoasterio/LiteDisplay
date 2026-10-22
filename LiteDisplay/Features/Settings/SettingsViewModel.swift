// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import Observation

/// App-wide preferences.
@MainActor
@Observable
final class SettingsViewModel {
    private(set) var isStrongFontSmoothing = false
    private(set) var launchAtLogin = false
    private(set) var loginRequiresApproval = false
    var error: LiteDisplayError?

    var reapplyOnConnect: Bool {
        didSet { settings.settings.reapplyOnConnect = reapplyOnConnect }
    }

    var showsWindowAtLaunch: Bool {
        didSet { settings.settings.showsWindowAtLaunch = showsWindowAtLaunch }
    }

    @ObservationIgnored private let fontSmoothing: any FontSmoothingControlling
    @ObservationIgnored private let loginItem: any LoginItemControlling
    @ObservationIgnored private let settings: any SettingsStoring

    init(fontSmoothing: any FontSmoothingControlling, loginItem: any LoginItemControlling, settings: any SettingsStoring) {
        self.fontSmoothing = fontSmoothing
        self.loginItem = loginItem
        self.settings = settings
        reapplyOnConnect = settings.settings.reapplyOnConnect
        showsWindowAtLaunch = settings.settings.showsWindowAtLaunch
    }

    var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }

    func refresh() {
        isStrongFontSmoothing = fontSmoothing.isStrongSmoothingEnabled()
        launchAtLogin = loginItem.isEnabled
        loginRequiresApproval = loginItem.requiresApproval
    }

    func setStrongFontSmoothing(_ enabled: Bool) {
        do {
            try fontSmoothing.setStrongSmoothing(enabled)
            error = nil
        } catch {
            self.error = error
        }
        refresh()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
            error = nil
        } catch {
            self.error = error
        }
        refresh()
    }

    func openLoginItemsSettings() {
        loginItem.openSystemSettings()
    }
}
