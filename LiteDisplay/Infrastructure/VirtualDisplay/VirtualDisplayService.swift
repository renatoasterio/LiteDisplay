// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import CoreGraphics

/// Creates a virtual display whose native mode is the panel's size at 2x (e.g. "looks like 1920×1080" backed by
/// 3840×2160) and mirrors the panel onto it, so the GPU renders at exactly 2x and downsamples 2:1. The virtual display lives as long as its
/// object is retained;
/// this service is its only owner. The private API is behind a runtime guard and weak linking.
///
/// A virtual display that took part in a configuration transaction is only removed by the window server when the
/// process exits (measured on macOS 27: still online 20 s after release). Deactivation therefore unmirrors, restores
/// the panel and reports `.lingering`; the app relaunches itself to free the display. Sleep uses suspend/resume,
/// which keeps the same virtual display instead of creating a new one per wake.
@MainActor
final class VirtualDisplayService: VirtualDisplayControlling {
    private static let requiredClasses = [
        "CGVirtualDisplay",
        "CGVirtualDisplayDescriptor",
        "CGVirtualDisplaySettings",
        "CGVirtualDisplayMode"
    ]
    private static let onlineTimeout: Duration = .seconds(3)
    private static let modeTableTimeout: Duration = .seconds(3)
    private static let removalTimeout: Duration = .milliseconds(1500)
    private static let pollInterval: Duration = .milliseconds(50)
    private static let fallbackRate = 60.0
    private static let fallbackSizeMM = CGSize(width: 600, height: 340)

    private struct Handle {
        let display: CGVirtualDisplay
        let virtualID: UInt32
        /// The panel was the main display: the virtual display takes the origin and the panel gets it back later.
        let keepsMain: Bool
    }

    /// Physical display id → virtual display mirrored by it.
    private var handles: [UInt32: Handle] = [:]
    /// Physical display id → virtual display kept alive while unmirrored for system sleep.
    private var suspended: [UInt32: Handle] = [:]
    /// Released virtual displays the window server has not removed yet.
    private var lingering: Set<UInt32> = []
    /// Makes every virtual display a new identity: the window server remembers the last mode per
    /// vendor/product/serial, and a remembered 1x mode would override the 2x default.
    private var activationCount: UInt32 = 0
    private let queue = DispatchQueue(label: "br.com.asoft.LiteDisplay.virtual-display")

    let isAvailable: Bool = VirtualDisplayService.requiredClasses.allSatisfy { NSClassFromString($0) != nil }

    var ownedDisplayIDs: Set<UInt32> {
        Set(handles.values.map(\.virtualID)).union(suspended.values.map(\.virtualID)).union(lingering)
    }

    var lingeringDisplayIDs: Set<UInt32> {
        lingering
    }

    func isActive(for displayID: UInt32) -> Bool {
        handles[displayID] != nil || suspended[displayID] != nil
    }

    func activate(for display: DisplaySnapshot) async throws(LiteDisplayError) {
        guard isAvailable else { throw .virtualDisplayUnavailable }
        guard handles[display.id] == nil else { return }
        guard let native = display.nativeMode else { throw .modeUnavailable }
        let panelRate = display.currentMode?.refreshRate ?? native.refreshRate

        let virtualDisplay = try makeVirtualDisplay(for: display, native: native, rate: panelRate)
        let virtualID = virtualDisplay.displayID
        handles[display.id] = Handle(display: virtualDisplay, virtualID: virtualID, keepsMain: display.isMain)
        Log.virtualDisplay.info("Created virtual display \(virtualID) for display \(display.id)")
        do {
            try await waitUntilOnline(virtualID)
            let virtualModes = try await waitForModeTable(virtualID)
            try mirror(
                physical: display.id,
                onto: virtualID,
                virtualModes: virtualModes,
                native: native,
                rate: panelRate,
                asMain: display.isMain
            )
        } catch {
            handles[display.id] = nil
            Log.virtualDisplay.error("Virtual display setup failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    @discardableResult
    func deactivate(for displayID: UInt32) async throws(LiteDisplayError) -> VirtualDisplayDeactivation {
        guard let handle = handles[displayID] ?? suspended[displayID] else { return .removed }
        if CGDisplayMirrorsDisplay(displayID) == handle.virtualID {
            try unmirror(physical: displayID, restoreMain: handle.keepsMain)
        }
        handles[displayID] = nil // releases the CGVirtualDisplay
        suspended[displayID] = nil
        Log.virtualDisplay.info("Released virtual display \(handle.virtualID)")
        if await waitUntilRemoved(handle.virtualID) {
            return .removed
        }
        lingering.insert(handle.virtualID)
        Log.virtualDisplay.notice("Virtual display \(handle.virtualID) lingers until the process exits")
        return .lingering
    }

    func deactivateAll() async {
        for displayID in Array(handles.keys) + Array(suspended.keys) {
            do {
                try await deactivate(for: displayID)
            } catch {
                Log.virtualDisplay
                    .error("Could not deactivate virtual display for \(displayID): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func suspendAll() {
        for (displayID, handle) in handles {
            if CGDisplayMirrorsDisplay(displayID) == handle.virtualID {
                do {
                    try unmirror(physical: displayID, restoreMain: handle.keepsMain)
                } catch {
                    Log.virtualDisplay
                        .error("Unmirror before sleep failed for \(displayID): \(error.localizedDescription, privacy: .public)")
                }
            }
            suspended[displayID] = handle
        }
        handles.removeAll()
    }

    func resumeAll() throws(LiteDisplayError) {
        let pending = suspended
        suspended.removeAll()
        for (displayID, handle) in pending {
            guard CGDisplayIsOnline(displayID) != 0, CGDisplayIsOnline(handle.virtualID) != 0 else {
                Log.virtualDisplay.notice("Virtual display \(handle.virtualID) or its panel went away during sleep")
                continue
            }
            let panelModes = DisplayModeCatalog.usableModes(for: displayID)
            let rate = DisplayModeCatalog.currentMode(of: displayID)?.refreshRate
            guard let native = ModeSelection.nativeMode(in: panelModes, preferredRate: rate) else { continue }
            let virtualModes = DisplayModeCatalog.usableModes(for: handle.virtualID)
            do {
                try mirror(
                    physical: displayID,
                    onto: handle.virtualID,
                    virtualModes: virtualModes,
                    native: native,
                    rate: native.refreshRate,
                    asMain: handle.keepsMain
                )
                handles[displayID] = handle
            } catch {
                lingering.insert(handle.virtualID)
                throw error
            }
        }
    }

    func releaseAll() {
        for (displayID, handle) in handles where CGDisplayMirrorsDisplay(displayID) == handle.virtualID {
            do {
                try unmirror(physical: displayID, restoreMain: handle.keepsMain)
            } catch {
                Log.virtualDisplay.error("Unmirror at exit failed for \(displayID): \(error.localizedDescription, privacy: .public)")
            }
        }
        handles.removeAll()
    }

    // MARK: - Private

    private func makeVirtualDisplay(
        for display: DisplaySnapshot,
        native: DisplayMode,
        rate: Double
    ) throws(LiteDisplayError) -> CGVirtualDisplay {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = "LiteDisplay – \(display.name)"
        descriptor.vendorID = DisplaySnapshot.virtualDisplayVendorID // macOS 14+ rejects a zero vendor id
        descriptor.productID = display.productID & 0xFFFF
        activationCount &+= 1
        descriptor.serialNum = UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970)) &+ activationCount
        descriptor.maxPixelsWide = UInt32(native.pixelWidth * 2)
        descriptor.maxPixelsHigh = UInt32(native.pixelHeight * 2)
        descriptor.sizeInMillimeters = display.physicalSize.isKnown
            ? CGSize(width: display.physicalSize.widthMM, height: display.physicalSize.heightMM)
            : Self.fallbackSizeMM
        // Generic RGB primaries, as BetterDummy uses.
        descriptor.redPrimary = CGPoint(x: 0.454, y: 0.242)
        descriptor.greenPrimary = CGPoint(x: 0.353, y: 0.674)
        descriptor.bluePrimary = CGPoint(x: 0.157, y: 0.084)
        descriptor.whitePoint = CGPoint(x: 0.950, y: 1.000)
        descriptor.queue = queue
        descriptor.terminationHandler = nil // a handler block is known to crash at process exit

        guard let virtualDisplay = CGVirtualDisplay(descriptor: descriptor) else { throw .virtualDisplayFailed("init") }

        // Mode sizes are in points: with hiDPI = 1 the window server also creates the 2x variant whenever
        // 2 × size fits maxPixelsWide/High. Listing the panel's native point size therefore yields a native
        // "looks like 1920×1080" mode backed by 3840×2160, which becomes the display's default: no mode change.
        let width = UInt32(native.width)
        let height = UInt32(native.height)
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        let fallback = CGVirtualDisplayMode(width: width, height: height, refreshRate: Self.fallbackRate)
        var modes = [CGVirtualDisplayMode(width: width, height: height, refreshRate: rate)]
        if abs(rate - Self.fallbackRate) >= DisplayMode.refreshRateTolerance {
            modes.append(fallback)
        }
        settings.modes = modes
        if !virtualDisplay.apply(settings) {
            settings.modes = [fallback]
            guard virtualDisplay.apply(settings) else { throw .virtualDisplayFailed("applySettings") }
        }
        return virtualDisplay
    }

    private func waitUntilOnline(_ virtualID: UInt32) async throws(LiteDisplayError) {
        let deadline = ContinuousClock.now + Self.onlineTimeout
        while CGDisplayIsOnline(virtualID) == 0 {
            guard ContinuousClock.now < deadline else { throw .virtualDisplayFailed("timeout") }
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    /// The mode table fills a few hundred milliseconds after the display reports online.
    private func waitForModeTable(_ virtualID: UInt32) async throws(LiteDisplayError) -> [DisplayMode] {
        let deadline = ContinuousClock.now + Self.modeTableTimeout
        while true {
            let modes = DisplayModeCatalog.usableModes(for: virtualID)
            if modes.contains(where: \.isHiDPI) {
                return modes
            }
            guard ContinuousClock.now < deadline else { throw .virtualDisplayFailed("no HiDPI mode") }
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    /// True when the window server dropped the display within `removalTimeout`.
    private func waitUntilRemoved(_ virtualID: UInt32) async -> Bool {
        let deadline = ContinuousClock.now + Self.removalTimeout
        while CGDisplayIsOnline(virtualID) != 0 {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: Self.pollInterval)
        }
        return true
    }

    private func mirror(
        physical: UInt32,
        onto virtualID: UInt32,
        virtualModes: [DisplayMode],
        native: DisplayMode,
        rate: Double,
        asMain: Bool
    ) throws(LiteDisplayError) {
        let target = ModeSelection.mode(in: virtualModes, size: native.size, hiDPI: true, preferredRate: rate)
            ?? virtualModes.filter(\.isHiDPI).max { $0.size < $1.size }
        guard let target, let cgTarget = DisplayModeCatalog.cgMode(matching: target, on: virtualID) else {
            throw .virtualDisplayFailed("no HiDPI mode")
        }

        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else { throw .configurationFailed(stage: "begin", code: begin.rawValue) }
        // Only set the mode when needed: changing it is what makes the display linger after release.
        if DisplayModeCatalog.currentMode(of: virtualID)?.id != target.id {
            let set = CGConfigureDisplayWithDisplayMode(config, virtualID, cgTarget, nil)
            guard set == .success else {
                CGCancelDisplayConfiguration(config)
                throw .configurationFailed(stage: "virtual mode", code: set.rawValue)
            }
        }
        let mirror = CGConfigureDisplayMirrorOfDisplay(config, physical, virtualID)
        guard mirror == .success else {
            CGCancelDisplayConfiguration(config)
            throw .configurationFailed(stage: "mirror", code: mirror.rawValue)
        }
        // The main display is the one at the origin. Setting the origin of the mirror *source* keeps the menu bar on
        // the panel; setting it on the mirroring panel would remove it from the set (CGDisplayConfiguration.h).
        if asMain {
            let origin = CGConfigureDisplayOrigin(config, virtualID, 0, 0)
            guard origin == .success else {
                CGCancelDisplayConfiguration(config)
                throw .configurationFailed(stage: "origin", code: origin.rawValue)
            }
        }
        // For the session only: the master vanishes with the app, so a permanent mirror record would be stale.
        let complete = CGCompleteDisplayConfiguration(config, .forSession)
        guard complete == .success else { throw .configurationFailed(stage: "complete", code: complete.rawValue) }
        guard CGDisplayMirrorsDisplay(physical) == virtualID else { throw .verificationFailed }
        restoreRateIfNeeded(physical: physical, native: native, rate: rate)
    }

    private func unmirror(physical: UInt32, restoreMain: Bool) throws(LiteDisplayError) {
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else { throw .configurationFailed(stage: "begin", code: begin.rawValue) }
        let unmirror = CGConfigureDisplayMirrorOfDisplay(config, physical, 0)
        guard unmirror == .success else {
            CGCancelDisplayConfiguration(config)
            throw .configurationFailed(stage: "unmirror", code: unmirror.rawValue)
        }
        if restoreMain {
            let origin = CGConfigureDisplayOrigin(config, physical, 0, 0)
            guard origin == .success else {
                CGCancelDisplayConfiguration(config)
                throw .configurationFailed(stage: "origin", code: origin.rawValue)
            }
        }
        let complete = CGCompleteDisplayConfiguration(config, .forSession)
        guard complete == .success else { throw .configurationFailed(stage: "complete", code: complete.rawValue) }
    }

    /// Joining a mirror set can drop the panel to a "safe" lower rate; put it back on its native timing.
    private func restoreRateIfNeeded(physical: UInt32, native: DisplayMode, rate: Double) {
        guard let current = DisplayModeCatalog.currentMode(of: physical), !current.matchesRefreshRate(rate),
              let wanted = ModeSelection.mode(
                  in: DisplayModeCatalog.usableModes(for: physical),
                  size: native.size,
                  hiDPI: false,
                  preferredRate: rate
              ),
              let cgWanted = DisplayModeCatalog.cgMode(matching: wanted, on: physical) else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
        guard CGConfigureDisplayWithDisplayMode(config, physical, cgWanted, nil) == .success else {
            CGCancelDisplayConfiguration(config)
            return
        }
        if CGCompleteDisplayConfiguration(config, .permanently) != .success {
            Log.virtualDisplay.warning("Could not restore \(rate, format: .fixed(precision: 0)) Hz on display \(physical)")
        }
    }
}
