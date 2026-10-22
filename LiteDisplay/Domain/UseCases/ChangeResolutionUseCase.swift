// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Changes size or refresh rate while keeping the active sharpness method.
@MainActor
struct ChangeResolutionUseCase {
    let sharpness: SetSharpnessUseCase

    @discardableResult
    func execute(
        display: DisplaySnapshot,
        size: DisplaySize? = nil,
        refreshRate: Double? = nil
    ) async throws(LiteDisplayError) -> DisplaySettings {
        let method = display.activeMethod
        guard method != .virtualDisplay else { throw .controlledByVirtualDisplay }
        let targetSize = size ?? display.currentMode?.size
        return try await sharpness.execute(.init(display: display, method: method, size: targetSize, refreshRate: refreshRate))
    }

    /// Applies an arbitrary mode from the full table, inferring the method from its scale.
    @discardableResult
    func execute(display: DisplaySnapshot, mode: DisplayMode) async throws(LiteDisplayError) -> DisplaySettings {
        guard display.activeMethod != .virtualDisplay else { throw .controlledByVirtualDisplay }
        let method: SharpnessMethod = mode.isHiDPI ? .hiDPI : .standard
        return try await sharpness.execute(.init(display: display, method: method, size: mode.size, refreshRate: mode.refreshRate))
    }
}
