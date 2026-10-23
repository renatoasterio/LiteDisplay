// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import Testing
@testable import LiteDisplay

@Suite("Colour temperature")
struct ColorTemperatureTests {
    @Test("6500 K is neutral")
    func neutral() {
        let gains = ColorTemperature.gains(kelvin: 6500)
        #expect(abs(gains.red - 1) < 0.001)
        #expect(abs(gains.green - 1) < 0.001)
        #expect(abs(gains.blue - 1) < 0.001)
    }

    @Test("Warmer temperatures cut blue first, then green, and keep red")
    func warm() {
        let gains = ColorTemperature.gains(kelvin: 2700)
        #expect(gains.red > 0.99)
        #expect(gains.green < gains.red)
        #expect(gains.blue < gains.green)
        #expect(gains.blue < 0.6)
        let milder = ColorTemperature.gains(kelvin: 4200)
        #expect(milder.blue > gains.blue)
        #expect(milder.blue < 1)
    }
}

@Suite("Blue light schedule")
struct BlueLightScheduleTests {
    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    @Test("A window crossing midnight is active late at night and early in the morning")
    func crossingMidnight() {
        let schedule = BlueLightSchedule.daily(start: TimeOfDay(hour: 18, minute: 0), end: TimeOfDay(hour: 7, minute: 0))
        #expect(schedule.isActive(at: date(23)))
        #expect(schedule.isActive(at: date(3)))
        #expect(schedule.isActive(at: date(18)))
        #expect(!schedule.isActive(at: date(7)))
        #expect(!schedule.isActive(at: date(12)))
    }

    @Test("A same-day window and the always schedule")
    func sameDay() {
        let schedule = BlueLightSchedule.daily(start: TimeOfDay(hour: 9, minute: 30), end: TimeOfDay(hour: 17, minute: 0))
        #expect(schedule.isActive(at: date(12)))
        #expect(!schedule.isActive(at: date(9, 15)))
        #expect(!schedule.isActive(at: date(20)))
        #expect(BlueLightSchedule.always.isActive(at: date(4)))
    }

    @Test("Settings decode with missing keys and clamp the temperature")
    func decoding() throws {
        let legacy = Data(#"{"reapplyOnConnect":false}"#.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)
        #expect(!decoded.reapplyOnConnect)
        #expect(decoded.blueLight == BlueLightSettings())
        let hot = BlueLightSettings(isEnabled: true, kelvin: 100, scope: .allDisplays, schedule: .always).sanitized
        #expect(hot.kelvin == BlueLightSettings.minimumKelvin)
    }
}

@Suite("Blue light use case and view model")
@MainActor
struct BlueLightUseCaseTests {
    struct Harness {
        let viewModel: ComfortViewModel
        let controller: FakeColorTemperatureController
        let settings: FakeSettingsStore
        let virtual: FakeVirtualDisplayController
    }

    private func makeHarness(scope: BlueLightScope = .externalDisplays) -> Harness {
        let base = UseCaseHarness()
        let controller = FakeColorTemperatureController()
        base.settings.settings.blueLight = BlueLightSettings(isEnabled: false, kelvin: 4200, scope: scope, schedule: .always)
        let useCase = ApplyBlueLightUseCase(
            displays: base.provider,
            virtualDisplays: base.virtual,
            colorTemperature: controller,
            settings: base.settings
        )
        let viewModel = ComfortViewModel(settings: base.settings, applyFilter: useCase)
        return Harness(viewModel: viewModel, controller: controller, settings: base.settings, virtual: base.virtual)
    }

    @Test("Enabling applies warm gains to the external displays and the virtual source")
    func enable() throws {
        let harness = makeHarness()
        harness.virtual.active = [3]
        harness.viewModel.isEnabled = true
        #expect(harness.viewModel.isActiveNow)
        #expect(harness.settings.settings.blueLight.isEnabled)
        let last = try #require(harness.controller.applied.last)
        #expect(last.gains.blue < 1)
        #expect(last.target == .displays([3, 1003]))
    }

    @Test("Disabling restores, and a schedule outside its window restores too")
    func disableAndSchedule() {
        let harness = makeHarness()
        harness.viewModel.isEnabled = true
        harness.viewModel.isEnabled = false
        #expect(!harness.viewModel.isActiveNow)
        #expect(harness.controller.restores >= 1)
        harness.viewModel.isEnabled = true
        harness.viewModel.usesSchedule = true
        let now = TimeOfDay.of(Date())
        harness.viewModel.scheduleStart = TimeOfDay(hour: (now.hour + 2) % 24, minute: 0)
        harness.viewModel.scheduleEnd = TimeOfDay(hour: (now.hour + 3) % 24, minute: 0)
        #expect(!harness.viewModel.isActiveNow)
    }

    @Test("All displays scope targets every online display")
    func allDisplays() {
        let harness = makeHarness(scope: .allDisplays)
        harness.viewModel.isEnabled = true
        #expect(harness.controller.applied.last?.target == .allOnline)
    }

    @Test("Failures are surfaced")
    func failure() {
        let harness = makeHarness()
        harness.controller.failure = .gammaFailed(code: 1000)
        harness.viewModel.isEnabled = true
        #expect(harness.viewModel.error == .gammaFailed(code: 1000))
    }
}
