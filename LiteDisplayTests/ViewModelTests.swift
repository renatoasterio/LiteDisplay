// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import Testing
@testable import LiteDisplay

@Suite("MonitorsViewModel")
@MainActor
struct MonitorsViewModelTests {
    func makeViewModel(display: DisplaySnapshot = Fixtures.fullHDDisplay()) -> (MonitorsViewModel, UseCaseHarness) {
        let harness = UseCaseHarness(display: display)
        let viewModel = MonitorsViewModel(
            provider: harness.provider,
            virtualDisplays: harness.virtual,
            sharpness: harness.sharpness,
            resolution: ChangeResolutionUseCase(sharpness: harness.sharpness),
            overrideInstaller: EnableHiDPIOverrideUseCase(installer: FakeOverrideInstaller()),
            reapply: ReapplyOnConnectUseCase(
                displays: harness.provider,
                profiles: harness.profiles,
                settings: harness.settings,
                sharpness: harness.sharpness
            )
        )
        viewModel.refresh()
        return (viewModel, harness)
    }

    @Test("Setting a method refreshes the displays and clears the busy flag")
    func setMethod() async {
        let (viewModel, _) = makeViewModel()
        await viewModel.setMethod(.hiDPI, for: viewModel.displays[0])
        #expect(viewModel.displays[0].activeMethod == .hiDPI)
        #expect(viewModel.error == nil)
        #expect(!viewModel.isApplying)
    }

    @Test("Errors are surfaced, not swallowed")
    func surfacesErrors() async {
        let (viewModel, harness) = makeViewModel()
        harness.modes.failure = .configurationFailed(stage: "complete", code: 1000)
        await viewModel.setMethod(.hiDPI, for: viewModel.displays[0])
        #expect(viewModel.error == .configurationFailed(stage: "complete", code: 1000))
        #expect(!viewModel.isApplying)
    }

    @Test("Quick toggle picks HiDPI when available, else the virtual display")
    func quickToggle() async {
        let (viewModel, _) = makeViewModel()
        await viewModel.setSharp(true, for: viewModel.displays[0])
        #expect(viewModel.displays[0].activeMethod == .hiDPI)
        let plain = Fixtures.display(modes: Fixtures.fullHDModesWithoutOverride(), current: nil)
        let (plainViewModel, _) = makeViewModel(display: plain)
        await plainViewModel.setSharp(true, for: plainViewModel.displays[0])
        #expect(plainViewModel.displays[0].activeMethod == .virtualDisplay)
    }

    @Test("A lingering virtual display schedules a relaunch after the mode was still applied")
    func lingeringVirtualDisplayRelaunches() async throws {
        let (viewModel, harness) = makeViewModel()
        harness.virtual.lingers = true
        var relaunched = false
        viewModel.relaunchHandler = { relaunched = true }
        await viewModel.setMethod(.virtualDisplay, for: viewModel.displays[0])
        #expect(viewModel.notice == nil)
        await viewModel.setMethod(.hiDPI, for: viewModel.displays[0])
        #expect(viewModel.displays[0].activeMethod == .hiDPI)
        #expect(viewModel.error == nil)
        #expect(viewModel.notice != nil)
        try await Task.sleep(for: .milliseconds(2300))
        #expect(relaunched)
    }

    @Test("Curated sizes and rates come from the display's own table")
    func derivedData() {
        let (viewModel, _) = makeViewModel()
        #expect(viewModel.curatedSizes(for: viewModel.displays[0]).count == 4)
        #expect(viewModel.refreshRates(for: viewModel.displays[0]).first == 240)
    }
}

@Suite("SettingsViewModel")
@MainActor
struct SettingsViewModelTests {
    @Test("Writes through to the services and the settings store")
    func writesThrough() {
        let fonts = FakeFontSmoothing()
        let login = FakeLoginItem()
        let settings = FakeSettingsStore()
        let viewModel = SettingsViewModel(fontSmoothing: fonts, loginItem: login, settings: settings)
        viewModel.setStrongFontSmoothing(true)
        viewModel.setLaunchAtLogin(true)
        viewModel.reapplyOnConnect = false
        #expect(fonts.strong)
        #expect(login.isEnabled)
        #expect(viewModel.isStrongFontSmoothing)
        #expect(viewModel.launchAtLogin)
        #expect(!settings.settings.reapplyOnConnect)
    }
}
