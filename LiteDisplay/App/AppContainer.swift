// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import Observation

/// Composition root. Builds every service once, wires them into the Domain protocols and owns the
/// app-lifetime view models. Views reach it through `@Environment(AppContainer.self)`.
@MainActor
@Observable
final class AppContainer {
    let settings: SettingsStore
    let profileStore: ProfileStore
    let displays: any DisplayProviding
    let virtualDisplays: any VirtualDisplayControlling

    let monitors: MonitorsViewModel
    let profiles: ProfilesViewModel
    let preferences: SettingsViewModel

    @ObservationIgnored private var sleepWake: SleepWakeObserver?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?

    init(
        settings: SettingsStore,
        profileStore: ProfileStore,
        displays: any DisplayProviding,
        virtualDisplays: any VirtualDisplayControlling,
        modes: any DisplayModeApplying,
        overrideInstaller: any OverrideInstalling,
        fontSmoothing: any FontSmoothingControlling,
        loginItem: any LoginItemControlling
    ) {
        self.settings = settings
        self.profileStore = profileStore
        self.displays = displays
        self.virtualDisplays = virtualDisplays

        let sharpness = SetSharpnessUseCase(displays: displays, modes: modes, virtualDisplays: virtualDisplays, settings: settings)
        let resolution = ChangeResolutionUseCase(sharpness: sharpness)
        let enableOverride = EnableHiDPIOverrideUseCase(installer: overrideInstaller)
        let reapply = ReapplyOnConnectUseCase(displays: displays, profiles: profileStore, settings: settings, sharpness: sharpness)
        monitors = MonitorsViewModel(
            provider: displays,
            virtualDisplays: virtualDisplays,
            sharpness: sharpness,
            resolution: resolution,
            overrideInstaller: enableOverride,
            reapply: reapply
        )
        profiles = ProfilesViewModel(
            store: profileStore,
            saveProfile: SaveProfileUseCase(displays: displays, profiles: profileStore),
            applyProfile: ApplyProfileUseCase(displays: displays, sharpness: sharpness)
        )
        preferences = SettingsViewModel(fontSmoothing: fontSmoothing, loginItem: loginItem, settings: settings)
        profiles.displaysDidChange = { [weak self] in self?.monitors.refresh() }
        monitors.relaunchHandler = { [weak self] in self?.relaunch() }
    }

    /// The production wiring.
    static func live() -> AppContainer {
        let virtualDisplays = VirtualDisplayService()
        return AppContainer(
            settings: SettingsStore(defaults: UserDefaults.standard),
            profileStore: ProfileStore(directory: ProfileStore.defaultDirectory()),
            displays: DisplayEnumerator(virtualDisplays: virtualDisplays),
            virtualDisplays: virtualDisplays,
            modes: DisplayModeService(),
            overrideInstaller: HiDPIOverrideInstaller(runner: PrivilegedRunner()),
            fontSmoothing: FontSmoothingService(),
            loginItem: LaunchAtLoginService()
        )
    }

    func start() {
        monitors.start()
        profiles.reload()
        preferences.refresh()
        sleepWake = SleepWakeObserver(
            onSleep: { [weak self] in self?.suspendVirtualDisplays() },
            onWake: { [weak self] in self?.resumeVirtualDisplays() }
        )
    }

    /// Synchronous on purpose: it runs inside `applicationShouldTerminate`, where awaiting a main-actor reply deadlocks.
    func shutdown() {
        monitors.stop()
        sleepWake?.stop()
        wakeTask?.cancel()
        virtualDisplays.releaseAll()
    }

    /// Starts a fresh instance and quits this one (the way out of a lingering virtual display).
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                Log.app.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    // MARK: - Sleep / wake

    /// A virtual mirror source is known to wedge system sleep: unmirror before sleeping, re-mirror after waking.
    private func suspendVirtualDisplays() {
        virtualDisplays.suspendAll()
    }

    private func resumeVirtualDisplays() {
        wakeTask?.cancel()
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            do {
                try virtualDisplays.resumeAll()
            } catch {
                Log.virtualDisplay.error("Could not restore virtual display after wake: \(error.localizedDescription, privacy: .public)")
            }
            monitors.refresh()
            monitors.relaunchIfVirtualDisplayLingers()
        }
    }
}
