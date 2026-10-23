// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Puts a display into one of the sharpness methods, optionally at a given size and refresh rate, and remembers it.
@MainActor
struct SetSharpnessUseCase {
    struct Request: Sendable {
        let display: DisplaySnapshot
        let method: SharpnessMethod
        var size: DisplaySize?
        var refreshRate: Double?
    }

    let displays: any DisplayProviding
    let modes: any DisplayModeApplying
    let virtualDisplays: any VirtualDisplayControlling
    let settings: any SettingsStoring

    @discardableResult
    func execute(_ request: Request) async throws(LiteDisplayError) -> DisplaySettings {
        let display = request.display
        let preferredRate = request.refreshRate ?? display.currentMode?.refreshRate
        let applied: DisplaySettings
        switch request.method {
        case .virtualDisplay:
            guard virtualDisplays.isAvailable else { throw .virtualDisplayUnavailable }
            if !virtualDisplays.isActive(for: display.id) {
                try ensureNativeMode(on: display, preferredRate: preferredRate)
                try await virtualDisplays.activate(for: display)
            }
            applied = DisplaySettings(method: .virtualDisplay, size: display.nativeSize, refreshRate: preferredRate)
        case .standard, .hiDPI:
            var current = display
            if virtualDisplays.isActive(for: display.id) {
                try await virtualDisplays.deactivate(for: display.id)
                // A mirrored panel reports a reduced mode table; re-read it now that it stands alone.
                current = displays.externalDisplays().first { $0.id == display.id } ?? display
            }
            let target = try selectMode(for: request, on: current, preferredRate: preferredRate)
            if modes.currentMode(of: display.id)?.id != target.id {
                try modes.apply(target, to: display.id)
            }
            applied = DisplaySettings(method: request.method, size: target.size, refreshRate: target.refreshRate)
        }
        settings.settings.displays[display.persistentID] = applied
        return applied
    }

    private func selectMode(
        for request: Request,
        on display: DisplaySnapshot,
        preferredRate: Double?
    ) throws(LiteDisplayError) -> DisplayMode {
        let modes = display.modes
        switch request.method {
        case .standard:
            if let size = request.size, let mode = ModeSelection.mode(in: modes, size: size, hiDPI: false, preferredRate: preferredRate) {
                return mode
            }
            guard let native = ModeSelection.nativeMode(in: modes, preferredRate: preferredRate) else { throw .modeUnavailable }
            return native
        case .hiDPI:
            guard display.hasUsableHiDPI else { throw .hiDPIUnavailable }
            if let size = request.size, let mode = ModeSelection.mode(in: modes, size: size, hiDPI: true, preferredRate: preferredRate) {
                return mode
            }
            guard let best = ModeSelection.bestHiDPIMode(in: modes, preferredRate: preferredRate) else { throw .hiDPIUnavailable }
            return best
        case .virtualDisplay:
            throw .modeUnavailable
        }
    }

    /// The physical panel should run its native timing while it mirrors the virtual display.
    private func ensureNativeMode(on display: DisplaySnapshot, preferredRate: Double?) throws(LiteDisplayError) {
        guard let native = ModeSelection.nativeMode(in: display.modes, preferredRate: preferredRate) else { return }
        if modes.currentMode(of: display.id)?.id != native.id {
            try modes.apply(native, to: display.id)
        }
    }
}
