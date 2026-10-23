// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreGraphics
import Foundation

/// Warms displays by scaling their own gamma tables (the f.lux approach, public Quartz Display Services API).
/// The calibration read before the first change is cached per display so repeated applies never compound,
/// and `restore()` hands every display back to its ColorSync profile. The window server resets gamma on
/// mode changes and on wake, so callers re-apply after display changes. Nothing persists past the process.
@MainActor
final class DisplayGammaService: ColorTemperatureControlling {
    private struct Calibration {
        let red: [CGGammaValue]
        let green: [CGGammaValue]
        let blue: [CGGammaValue]
    }

    private static let maxDisplays: UInt32 = 32

    /// Display id → gamma table as it was before LiteDisplay touched it.
    private var calibrations: [UInt32: Calibration] = [:]
    private var applied: Set<UInt32> = []

    func apply(_ gains: ChannelGains, to target: ColorTemperatureTarget) throws(LiteDisplayError) {
        pruneOffline()
        let ids: [UInt32] = switch target {
        case let .displays(set): set.filter { CGDisplayIsOnline($0) != 0 }.sorted()
        case .allOnline: Self.onlineDisplayIDs()
        }
        for id in applied.subtracting(ids) {
            restoreDisplay(id)
        }
        for id in ids {
            let calibration = try calibration(for: id)
            var red = calibration.red.map { $0 * CGGammaValue(gains.red) }
            var green = calibration.green.map { $0 * CGGammaValue(gains.green) }
            var blue = calibration.blue.map { $0 * CGGammaValue(gains.blue) }
            let result = CGSetDisplayTransferByTable(id, UInt32(red.count), &red, &green, &blue)
            guard result == .success else { throw .gammaFailed(code: result.rawValue) }
            applied.insert(id)
        }
        if !ids.isEmpty {
            let blue = gains.blue
            Log.system.info("Applied blue gain \(blue, format: .fixed(precision: 3)) to \(ids.count) display(s)")
        }
    }

    func restore() {
        guard !applied.isEmpty else { return }
        CGDisplayRestoreColorSyncSettings()
        applied.removeAll()
        Log.system.info("Restored display calibrations")
    }

    // MARK: - Private

    private func calibration(for id: UInt32) throws(LiteDisplayError) -> Calibration {
        if let cached = calibrations[id] {
            return cached
        }
        let capacity = Int(CGDisplayGammaTableCapacity(id))
        guard capacity > 0 else { throw .gammaFailed(code: 0) }
        var red = [CGGammaValue](repeating: 0, count: capacity)
        var green = [CGGammaValue](repeating: 0, count: capacity)
        var blue = [CGGammaValue](repeating: 0, count: capacity)
        var count: UInt32 = 0
        let result = CGGetDisplayTransferByTable(id, UInt32(capacity), &red, &green, &blue, &count)
        guard result == .success, count > 0 else { throw .gammaFailed(code: result.rawValue) }
        let samples = Int(count)
        let calibration = Calibration(
            red: Array(red.prefix(samples)),
            green: Array(green.prefix(samples)),
            blue: Array(blue.prefix(samples))
        )
        calibrations[id] = calibration
        return calibration
    }

    private func restoreDisplay(_ id: UInt32) {
        defer { applied.remove(id) }
        guard CGDisplayIsOnline(id) != 0, let calibration = calibrations[id] else { return }
        var red = calibration.red
        var green = calibration.green
        var blue = calibration.blue
        if CGSetDisplayTransferByTable(id, UInt32(red.count), &red, &green, &blue) != .success {
            Log.system.warning("Could not restore the gamma table of display \(id)")
        }
    }

    /// Display ids are reused across connections; a table cached for a gone display must not be applied to a new one.
    private func pruneOffline() {
        calibrations = calibrations.filter { CGDisplayIsOnline($0.key) != 0 }
        applied = applied.filter { CGDisplayIsOnline($0) != 0 }
    }

    private static func onlineDisplayIDs() -> [UInt32] {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        guard CGGetOnlineDisplayList(maxDisplays, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}
