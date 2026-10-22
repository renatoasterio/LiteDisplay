// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AppKit
import CoreGraphics

/// Creates a 2x virtual display the size of the panel's backing store and mirrors the panel onto it, so the
/// GPU renders at exactly 2x and downsamples 2:1. The virtual display lives as long as its object is retained;
/// this service is its only owner. The private API is behind a runtime guard and weak linking.
@MainActor
final class VirtualDisplayService: VirtualDisplayControlling {
    private static let requiredClasses = [
        "CGVirtualDisplay",
        "CGVirtualDisplayDescriptor",
        "CGVirtualDisplaySettings",
        "CGVirtualDisplayMode"
    ]
    private static let onlineTimeout: Duration = .seconds(3)
    private static let removalTimeout: Duration = .seconds(2)
    private static let pollInterval: Duration = .milliseconds(50)
    private static let fallbackRate = 60.0
    private static let fallbackSizeMM = CGSize(width: 600, height: 340)

    private struct Handle {
        let display: CGVirtualDisplay
        let virtualID: UInt32
    }

    /// Physical display id → virtual display mirrored by it.
    private var handles: [UInt32: Handle] = [:]
    private let queue = DispatchQueue(label: "br.com.asoft.LiteDisplay.virtual-display")

    let isAvailable: Bool = VirtualDisplayService.requiredClasses.allSatisfy { NSClassFromString($0) != nil }

    var ownedDisplayIDs: Set<UInt32> {
        Set(handles.values.map(\.virtualID))
    }

    func isActive(for displayID: UInt32) -> Bool {
        handles[displayID] != nil
    }

    func activate(for display: DisplaySnapshot) async throws(LiteDisplayError) {
        guard isAvailable else { throw .virtualDisplayUnavailable }
        guard handles[display.id] == nil else { return }
        guard let native = display.nativeMode else { throw .modeUnavailable }
        let panelRate = display.currentMode?.refreshRate ?? native.refreshRate

        let virtualDisplay = try makeVirtualDisplay(for: display, native: native, rate: panelRate)
        let virtualID = virtualDisplay.displayID
        handles[display.id] = Handle(display: virtualDisplay, virtualID: virtualID)
        Log.virtualDisplay.info("Created virtual display \(virtualID) for display \(display.id)")
        do {
            try await waitUntilOnline(virtualID)
            try mirror(physical: display.id, onto: virtualID, native: native, rate: panelRate)
        } catch {
            handles[display.id] = nil
            Log.virtualDisplay.error("Virtual display setup failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func deactivate(for displayID: UInt32) async throws(LiteDisplayError) {
        guard let handle = handles[displayID] else { return }
        if CGDisplayMirrorsDisplay(displayID) == handle.virtualID {
            try unmirror(physical: displayID)
        }
        handles[displayID] = nil // releases the CGVirtualDisplay; the window server removes the display
        Log.virtualDisplay.info("Released virtual display \(handle.virtualID)")
        try await waitUntilRemoved(handle.virtualID)
    }

    func deactivateAll() async {
        for displayID in Array(handles.keys) {
            do {
                try await deactivate(for: displayID)
            } catch {
                Log.virtualDisplay
                    .error("Could not deactivate virtual display for \(displayID): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func releaseAll() {
        for (displayID, handle) in handles where CGDisplayMirrorsDisplay(displayID) == handle.virtualID {
            do {
                try unmirror(physical: displayID)
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
        descriptor.serialNum = display.serialNumber &+ 1 // distinct from the panel, stable across launches
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

        let width = UInt32(native.pixelWidth * 2)
        let height = UInt32(native.pixelHeight * 2)
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

    /// The go-macos/virtualdisplay project documents that a virtual display whose mode was changed can linger
    /// until the process exits; the UI offers a relaunch in that case.
    private func waitUntilRemoved(_ virtualID: UInt32) async throws(LiteDisplayError) {
        let deadline = ContinuousClock.now + Self.removalTimeout
        while CGDisplayIsOnline(virtualID) != 0 {
            guard ContinuousClock.now < deadline else { throw .virtualDisplayLingering }
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    private func mirror(physical: UInt32, onto virtualID: UInt32, native: DisplayMode, rate: Double) throws(LiteDisplayError) {
        let virtualModes = DisplayModeCatalog.usableModes(for: virtualID)
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
        // For the session only: the master vanishes with the app, so a permanent mirror record would be stale.
        let complete = CGCompleteDisplayConfiguration(config, .forSession)
        guard complete == .success else { throw .configurationFailed(stage: "complete", code: complete.rawValue) }
        guard CGDisplayMirrorsDisplay(physical) == virtualID else { throw .verificationFailed }
        restoreRateIfNeeded(physical: physical, native: native, rate: rate)
    }

    private func unmirror(physical: UInt32) throws(LiteDisplayError) {
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else { throw .configurationFailed(stage: "begin", code: begin.rawValue) }
        let unmirror = CGConfigureDisplayMirrorOfDisplay(config, physical, 0)
        guard unmirror == .success else {
            CGCancelDisplayConfiguration(config)
            throw .configurationFailed(stage: "unmirror", code: unmirror.rawValue)
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
