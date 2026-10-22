// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import Testing
@testable import LiteDisplay

@MainActor
struct UseCaseHarness {
    let provider: FakeDisplayProvider
    let modes = FakeModeApplier()
    let virtual = FakeVirtualDisplayController()
    let settings = FakeSettingsStore()
    let profiles = FakeProfileStore()
    let sharpness: SetSharpnessUseCase

    init(display: DisplaySnapshot = Fixtures.fullHDDisplay()) {
        provider = FakeDisplayProvider(displays: [display])
        modes.provider = provider
        virtual.provider = provider
        modes.current[display.id] = display.currentMode
        sharpness = SetSharpnessUseCase(modes: modes, virtualDisplays: virtual, settings: settings)
    }

    var display: DisplaySnapshot {
        provider.displays[0]
    }
}

@Suite("SetSharpnessUseCase")
@MainActor
struct SetSharpnessUseCaseTests {
    @Test("HiDPI applies the best mode at the current rate and persists it")
    func hiDPI() async throws {
        let harness = UseCaseHarness()
        let applied = try await harness.sharpness.execute(.init(display: harness.display, method: .hiDPI))
        #expect(harness.modes.applied.count == 1)
        #expect(harness.modes.applied[0].mode.size == DisplaySize(width: 1904, height: 1071))
        #expect(harness.modes.applied[0].mode.refreshRate == 120)
        #expect(applied.method == .hiDPI)
        #expect(harness.settings.settings.displays[harness.display.persistentID] == applied)
    }

    @Test("Standard returns to the native mode and skips the apply when already there")
    func standard() async throws {
        let harness = UseCaseHarness()
        try await harness.sharpness.execute(.init(display: harness.display, method: .standard))
        #expect(harness.modes.applied.isEmpty)
        try await harness.sharpness.execute(.init(display: harness.display, method: .hiDPI))
        try await harness.sharpness.execute(.init(display: harness.display, method: .standard))
        #expect(harness.modes.applied.last?.mode.isNative1x == true)
        #expect(harness.modes.applied.last?.mode.refreshRate == 120)
    }

    @Test("A size and rate can be chosen explicitly")
    func explicitSize() async throws {
        let harness = UseCaseHarness()
        let applied = try await harness.sharpness.execute(.init(
            display: harness.display,
            method: .hiDPI,
            size: DisplaySize(width: 1600, height: 900),
            refreshRate: 60
        ))
        #expect(applied.size == DisplaySize(width: 1600, height: 900))
        #expect(applied.refreshRate == 60)
    }

    @Test("Virtual display activates after putting the panel on its native mode")
    func virtualDisplay() async throws {
        let hiDPI = Fixtures.mode(in: Fixtures.fullHDModes(), 1600, 900, scale: 2, rate: 120)
        let harness = UseCaseHarness(display: Fixtures.fullHDDisplay(current: hiDPI))
        try await harness.sharpness.execute(.init(display: harness.display, method: .virtualDisplay))
        #expect(harness.modes.applied.count == 1)
        #expect(harness.modes.applied[0].mode.isNative1x)
        #expect(harness.virtual.activations == 1)
        #expect(harness.settings.settings.displays[harness.display.persistentID]?.method == .virtualDisplay)
    }

    @Test("Leaving the virtual display deactivates it before switching modes")
    func leaveVirtual() async throws {
        let harness = UseCaseHarness()
        try await harness.sharpness.execute(.init(display: harness.display, method: .virtualDisplay))
        try await harness.sharpness.execute(.init(display: harness.display, method: .hiDPI))
        #expect(harness.virtual.deactivations == 1)
        #expect(harness.virtual.active.isEmpty)
        #expect(harness.modes.applied.last?.mode.isHiDPI == true)
    }

    @Test("HiDPI without usable modes fails with a recovery suggestion")
    func hiDPIUnavailable() async {
        let plain = Fixtures.display(modes: Fixtures.fullHDModesWithoutOverride(), current: nil)
        let harness = UseCaseHarness(display: plain)
        await #expect(throws: LiteDisplayError.hiDPIUnavailable) {
            try await harness.sharpness.execute(.init(display: plain, method: .hiDPI))
        }
        #expect(LiteDisplayError.hiDPIUnavailable.recoverySuggestion != nil)
    }

    @Test("Virtual display unavailable on this macOS is reported")
    func virtualUnavailable() async {
        let harness = UseCaseHarness()
        harness.virtual.isAvailable = false
        await #expect(throws: LiteDisplayError.virtualDisplayUnavailable) {
            try await harness.sharpness.execute(.init(display: harness.display, method: .virtualDisplay))
        }
    }
}

@Suite("ChangeResolutionUseCase")
@MainActor
struct ChangeResolutionUseCaseTests {
    @Test("Keeps the active method")
    func keepsMethod() async throws {
        let hiDPI = Fixtures.mode(in: Fixtures.fullHDModes(), 1904, 1071, scale: 2, rate: 120)
        let harness = UseCaseHarness(display: Fixtures.fullHDDisplay(current: hiDPI))
        let useCase = ChangeResolutionUseCase(sharpness: harness.sharpness)
        let applied = try await useCase.execute(display: harness.display, refreshRate: 240)
        #expect(applied.method == .hiDPI)
        #expect(applied.size == hiDPI.size)
        #expect(applied.refreshRate == 240)
    }

    @Test("Refuses while the virtual display controls the panel")
    func refusesVirtual() async {
        let harness = UseCaseHarness(display: Fixtures.display(modes: Fixtures.fullHDModes(), current: nil, mirroringVirtual: true))
        let useCase = ChangeResolutionUseCase(sharpness: harness.sharpness)
        await #expect(throws: LiteDisplayError.controlledByVirtualDisplay) {
            try await useCase.execute(display: harness.display, size: DisplaySize(width: 1600, height: 900))
        }
    }
}

@Suite("Profiles")
@MainActor
struct ProfileUseCaseTests {
    @Test("Saving captures every connected display")
    func save() throws {
        let harness = UseCaseHarness()
        let useCase = SaveProfileUseCase(displays: harness.provider, profiles: harness.profiles)
        let profile = try useCase.execute(name: "  Trabalho ", color: .cyan, symbolName: "briefcase", applyOnConnect: true)
        #expect(profile.name == "Trabalho")
        #expect(profile.displays[harness.display.persistentID]?.method == .standard)
        #expect(harness.profiles.profiles.count == 1)
    }

    @Test("Saving without a name fails")
    func saveWithoutName() {
        let harness = UseCaseHarness()
        let useCase = SaveProfileUseCase(displays: harness.provider, profiles: harness.profiles)
        #expect(throws: LiteDisplayError.self) {
            try useCase.execute(name: "  ", color: .cyan, symbolName: "briefcase", applyOnConnect: false)
        }
    }

    @Test("Applying touches covered displays only and skips satisfied ones")
    func apply() async throws {
        let harness = UseCaseHarness()
        let useCase = ApplyProfileUseCase(displays: harness.provider, sharpness: harness.sharpness)
        let wanted = DisplaySettings(method: .hiDPI, size: DisplaySize(width: 1600, height: 900), refreshRate: 60)
        let profile = Profile(name: "Filmes", displays: [harness.display.persistentID: wanted])
        #expect(try await useCase.execute(profile) == 1)
        #expect(try await useCase.execute(profile) == 0)
        let other = Profile(name: "Outro", displays: ["unknown": wanted])
        #expect(try await useCase.execute(other) == 0)
    }

    @Test("Reapply on connect prefers the profile marked for it over the last settings")
    func reapply() async throws {
        let harness = UseCaseHarness()
        harness.settings.settings.displays[harness.display.persistentID] = DisplaySettings(
            method: .hiDPI,
            size: DisplaySize(width: 1440, height: 810),
            refreshRate: 60
        )
        let wanted = DisplaySettings(method: .hiDPI, size: DisplaySize(width: 1600, height: 900), refreshRate: 120)
        harness.profiles.profiles = [Profile(name: "Trabalho", displays: [harness.display.persistentID: wanted], applyOnConnect: true)]
        let useCase = ReapplyOnConnectUseCase(
            displays: harness.provider,
            profiles: harness.profiles,
            settings: harness.settings,
            sharpness: harness.sharpness
        )
        #expect(try await useCase.execute(displayID: harness.display.id))
        #expect(harness.modes.applied.last?.mode.size == DisplaySize(width: 1600, height: 900))
        #expect(try await useCase.execute(displayID: harness.display.id) == false)
        harness.settings.settings.reapplyOnConnect = false
        #expect(try await useCase.execute(displayID: 99) == false)
    }

    @Test("Override use case builds a profile from the panel's native size")
    func overrideProfile() async throws {
        let installer = FakeOverrideInstaller()
        let useCase = EnableHiDPIOverrideUseCase(installer: installer)
        let profile = try await useCase.execute(for: Fixtures.fullHDDisplay())
        #expect(profile.nativeSize == DisplaySize(width: 1920, height: 1080))
        #expect(installer.installed == [profile])
    }
}
