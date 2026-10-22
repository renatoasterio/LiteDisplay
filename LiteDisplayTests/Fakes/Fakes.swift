// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
@testable import LiteDisplay

@MainActor
final class FakeDisplayProvider: DisplayProviding {
    var displays: [DisplaySnapshot]
    let changes: AsyncStream<DisplayChange>
    let continuation: AsyncStream<DisplayChange>.Continuation

    init(displays: [DisplaySnapshot] = []) {
        self.displays = displays
        let (stream, continuation) = AsyncStream.makeStream(of: DisplayChange.self)
        changes = stream
        self.continuation = continuation
    }

    func externalDisplays() -> [DisplaySnapshot] {
        displays
    }

    /// Simulates the window server: replaces a display's current mode after an apply.
    func update(displayID: UInt32, currentMode: DisplayMode?, mirroringVirtual: Bool? = nil) {
        displays = displays.map { display in
            guard display.id == displayID else { return display }
            return Fixtures.display(
                id: display.id,
                persistentID: display.persistentID,
                modes: display.modes,
                current: currentMode,
                mirroringVirtual: mirroringVirtual ?? display.isMirroringVirtualDisplay,
                physical: display.physicalSize
            )
        }
    }
}

@MainActor
final class FakeModeApplier: DisplayModeApplying {
    var current: [UInt32: DisplayMode] = [:]
    var applied: [(displayID: UInt32, mode: DisplayMode)] = []
    var failure: LiteDisplayError?
    /// Keeps the provider's snapshots in sync with what was applied.
    var provider: FakeDisplayProvider?

    func apply(_ mode: DisplayMode, to displayID: UInt32) throws(LiteDisplayError) {
        if let failure {
            throw failure
        }
        applied.append((displayID, mode))
        current[displayID] = mode
        provider?.update(displayID: displayID, currentMode: mode)
    }

    func currentMode(of displayID: UInt32) -> DisplayMode? {
        current[displayID]
    }
}

@MainActor
final class FakeVirtualDisplayController: VirtualDisplayControlling {
    var isAvailable = true
    var active: Set<UInt32> = []
    var activations = 0
    var deactivations = 0
    var failure: LiteDisplayError?
    var provider: FakeDisplayProvider?

    var ownedDisplayIDs: Set<UInt32> {
        Set(active.map { $0 + 1000 })
    }

    func isActive(for displayID: UInt32) -> Bool {
        active.contains(displayID)
    }

    func activate(for display: DisplaySnapshot) async throws(LiteDisplayError) {
        if let failure {
            throw failure
        }
        active.insert(display.id)
        activations += 1
        provider?.update(displayID: display.id, currentMode: display.currentMode, mirroringVirtual: true)
    }

    func deactivate(for displayID: UInt32) async throws(LiteDisplayError) {
        active.remove(displayID)
        deactivations += 1
        provider?.update(
            displayID: displayID,
            currentMode: provider?.displays.first { $0.id == displayID }?.currentMode,
            mirroringVirtual: false
        )
    }

    func deactivateAll() async {
        for displayID in active {
            try? await deactivate(for: displayID)
        }
    }

    func releaseAll() {
        deactivations += active.count
        active.removeAll()
    }
}

/// Test-only; state is touched from one test at a time.
final class FakeOverrideInstaller: OverrideInstalling, @unchecked Sendable {
    var installed: [HiDPIOverrideProfile] = []
    var failure: LiteDisplayError?

    func isInstalled(_ profile: HiDPIOverrideProfile) -> Bool {
        installed.contains(profile)
    }

    func install(_ profile: HiDPIOverrideProfile) async throws(LiteDisplayError) {
        if let failure {
            throw failure
        }
        installed.append(profile)
    }
}

/// Test-only; records the commands it would have run as administrator.
final class FakePrivilegedExecutor: PrivilegedExecuting, @unchecked Sendable {
    var commands: [String] = []
    var failure: LiteDisplayError?

    func run(_ command: String, prompt: String) async throws(LiteDisplayError) {
        if let failure {
            throw failure
        }
        commands.append(command)
    }
}

@MainActor
final class FakeSettingsStore: SettingsStoring {
    var settings = AppSettings()
}

@MainActor
final class FakeProfileStore: ProfileStoring {
    var profiles: [Profile] = []
    var failure: LiteDisplayError?

    func upsert(_ profile: Profile) throws(LiteDisplayError) {
        if let failure {
            throw failure
        }
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
    }

    func delete(id: UUID) throws(LiteDisplayError) {
        if let failure {
            throw failure
        }
        profiles.removeAll { $0.id == id }
    }
}

@MainActor
final class FakeFontSmoothing: FontSmoothingControlling {
    var strong = false
    func isStrongSmoothingEnabled() -> Bool {
        strong
    }

    func setStrongSmoothing(_ enabled: Bool) throws(LiteDisplayError) {
        strong = enabled
    }
}

@MainActor
final class FakeLoginItem: LoginItemControlling {
    var isEnabled = false
    var requiresApproval = false
    var opened = false
    func setEnabled(_ enabled: Bool) throws(LiteDisplayError) {
        isEnabled = enabled
    }

    func openSystemSettings() {
        opened = true
    }
}
