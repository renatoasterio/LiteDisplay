// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation
import Testing
@testable import LiteDisplay

@Suite("Mode selection")
struct ModeSelectionTests {
    let fullHD = Fixtures.fullHDModes()

    @Test("Native mode keeps the preferred refresh rate")
    func nativeKeepsRate() {
        let native = ModeSelection.nativeMode(in: fullHD, preferredRate: 120)
        #expect(native?.size == DisplaySize(width: 1920, height: 1080))
        #expect(native?.isHiDPI == false)
        #expect(native?.refreshRate == 120)
    }

    @Test("Native mode falls back to the highest rate")
    func nativeFallsBack() {
        #expect(ModeSelection.nativeMode(in: fullHD, preferredRate: 75)?.refreshRate == 240)
        #expect(ModeSelection.nativeMode(in: fullHD, preferredRate: nil)?.refreshRate == 240)
    }

    @Test("Best HiDPI mode is the largest size below the panel, at the preferred rate")
    func bestHiDPI() {
        let best = ModeSelection.bestHiDPIMode(in: fullHD, preferredRate: 120)
        #expect(best?.size == DisplaySize(width: 1904, height: 1071))
        #expect(best?.pixelSize == DisplaySize(width: 3808, height: 2142))
        #expect(best?.refreshRate == 120)
    }

    @Test("Curated sizes for a 1080p panel with override")
    func curatedFullHD() {
        let sizes = ModeSelection.curatedSizes(in: fullHD, including: nil)
        #expect(sizes.map(\.size.width) == [1904, 1600, 1440, 1280])
        #expect(sizes.map(\.tier) == [.standard, .larger, .muchLarger, .huge])
    }

    @Test("Curated sizes keep the active size as custom")
    func curatedIncludesActive() {
        let sizes = ModeSelection.curatedSizes(in: fullHD, including: DisplaySize(width: 1712, height: 963))
        #expect(sizes.contains { $0.size.width == 1712 && $0.tier == .custom })
    }

    @Test("Curated sizes for a 4K panel use the exact 2:1 size as standard")
    func curated4K() {
        let sizes = ModeSelection.curatedSizes(in: Fixtures.fourKModes(), including: nil)
        #expect(sizes.first { $0.tier == .standard }?.size == DisplaySize(width: 1920, height: 1080))
        #expect(sizes.first { $0.tier == .moreSpace }?.size == DisplaySize(width: 2560, height: 1440))
    }

    @Test("Refresh rates are unique and descending")
    func refreshRates() {
        let rates = ModeSelection.refreshRates(in: fullHD, size: DisplaySize(width: 1904, height: 1071), hiDPI: true)
        #expect(rates == [240, 144, 120, 60, 50, 30])
    }

    @Test("Usable HiDPI ignores Apple's stock half-resolution mode")
    func usableHiDPI() {
        let without = Fixtures.display(modes: Fixtures.fullHDModesWithoutOverride(), current: nil)
        #expect(!without.hasUsableHiDPI)
        #expect(Fixtures.fullHDDisplay().hasUsableHiDPI)
    }

    @Test("Active method follows the current mode and the mirror state")
    func activeMethod() {
        let hiDPI = Fixtures.mode(in: fullHD, 1904, 1071, scale: 2, rate: 120)
        #expect(Fixtures.fullHDDisplay().activeMethod == .standard)
        #expect(Fixtures.fullHDDisplay(current: hiDPI).activeMethod == .hiDPI)
        #expect(Fixtures.display(modes: fullHD, current: nil, mirroringVirtual: true).activeMethod == .virtualDisplay)
    }

    @Test("Settings are satisfied only by a matching display state")
    func settingsSatisfied() {
        let hiDPI = Fixtures.mode(in: fullHD, 1904, 1071, scale: 2, rate: 120)
        let display = Fixtures.fullHDDisplay(current: hiDPI)
        #expect(DisplaySettings(method: .hiDPI, size: hiDPI.size, refreshRate: 120).isSatisfied(by: display))
        #expect(!DisplaySettings(method: .hiDPI, size: hiDPI.size, refreshRate: 60).isSatisfied(by: display))
        #expect(!DisplaySettings(method: .standard).isSatisfied(by: display))
    }
}
