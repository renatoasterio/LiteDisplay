// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// A "looks like" size offered to the user, with the tier it fills.
struct CuratedSize: Hashable, Sendable, Identifiable {
    enum Tier: String, Sendable, CaseIterable {
        /// Wider than the standard HiDPI size (Retina-class panels only).
        case moreSpace
        /// The sharp size that keeps the usual amount of space.
        case standard
        case larger
        case muchLarger
        case huge
        /// Whatever is active but outside the curated ladder.
        case custom
    }

    let size: DisplaySize
    let tier: Tier

    var id: DisplaySize {
        size
    }
}

/// Pure mode-selection rules. Everything here is deterministic over a mode list, so it is unit-tested.
enum ModeSelection {
    /// Tiers as a fraction of the standard HiDPI width.
    static let tierFactors: [(CuratedSize.Tier, Double)] = [
        (.moreSpace, 4.0 / 3.0), (.standard, 1.0), (.larger, 5.0 / 6.0), (.muchLarger, 3.0 / 4.0), (.huge, 2.0 / 3.0)
    ]
    /// A candidate counts for a tier when its width is within this fraction of the target.
    static let tierTolerance = 0.04
    static let aspectTolerance = 0.02
    static let minimumCandidateWidth = 1280

    /// The panel's own 1x mode at the preferred rate (or the highest rate).
    static func nativeMode(in modes: [DisplayMode], preferredRate: Double?) -> DisplayMode? {
        var natives = modes.filter(\.isNative1x)
        if natives.isEmpty {
            let largest = modes.filter { !$0.isHiDPI }.map(\.pixelSize).max()
            natives = modes.filter { !$0.isHiDPI && $0.pixelSize == largest }
        }
        return pick(natives, preferredRate: preferredRate)
    }

    /// HiDPI modes below the native size with the panel's aspect ratio.
    static func hiDPICandidates(in modes: [DisplayMode]) -> [DisplayMode] {
        guard let native = nativeMode(in: modes, preferredRate: nil)?.size else { return [] }
        return modes.filter { mode in
            mode.isHiDPI
                && mode.width <= native.width && mode.height <= native.height
                && mode.width >= minimumCandidateWidth
                && abs(mode.size.aspectRatio - native.aspectRatio) < aspectTolerance
        }
    }

    /// The sharp size that keeps the usual amount of space: exact 2:1 over the panel when offered, else the largest HiDPI size.
    static func standardHiDPISize(in modes: [DisplayMode]) -> DisplaySize? {
        let candidates = hiDPICandidates(in: modes)
        guard let native = nativeMode(in: modes, preferredRate: nil)?.pixelSize else { return nil }
        if let exact = candidates.first(where: { $0.pixelSize == native }) {
            return exact.size
        }
        return candidates.map(\.size).max()
    }

    static func bestHiDPIMode(in modes: [DisplayMode], preferredRate: Double?) -> DisplayMode? {
        guard let size = standardHiDPISize(in: modes) else { return nil }
        return mode(in: modes, size: size, hiDPI: true, preferredRate: preferredRate)
    }

    /// The mode with the given size and scale, at the preferred rate (or the highest rate).
    static func mode(in modes: [DisplayMode], size: DisplaySize, hiDPI: Bool, preferredRate: Double?) -> DisplayMode? {
        pick(modes.filter { $0.size == size && $0.isHiDPI == hiDPI }, preferredRate: preferredRate)
    }

    /// The curated ladder of HiDPI sizes, plus the active size when it is not on the ladder.
    static func curatedSizes(in modes: [DisplayMode], including active: DisplaySize?) -> [CuratedSize] {
        let sizes = Set(hiDPICandidates(in: modes).map(\.size))
        guard let standard = standardHiDPISize(in: modes), let native = nativeMode(in: modes, preferredRate: nil) else { return [] }
        // Tiers are fractions of the exact 2:1 width when the panel offers it; otherwise of the native width,
        // so a 1080p panel with an override lands on 1600, 1440 and 1280 rather than odd neighbours of 1904.
        let referenceWidth = standard.doubled == native.pixelSize ? standard.width : native.width
        var result: [CuratedSize] = []
        for (tier, factor) in tierFactors {
            let targetWidth = Double(referenceWidth) * factor
            let pick: DisplaySize? = tier == .standard
                ? standard
                : sizes.min { abs(Double($0.width) - targetWidth) < abs(Double($1.width) - targetWidth) }
            guard let pick, abs(Double(pick.width) - targetWidth) <= targetWidth * tierTolerance,
                  !result.contains(where: { $0.size == pick }) else { continue }
            result.append(CuratedSize(size: pick, tier: tier))
        }
        if let active, sizes.contains(active), !result.contains(where: { $0.size == active }) {
            result.append(CuratedSize(size: active, tier: .custom))
        }
        return result.sorted { $0.size > $1.size }
    }

    /// Distinct refresh rates for a size and scale, highest first.
    static func refreshRates(in modes: [DisplayMode], size: DisplaySize, hiDPI: Bool) -> [Double] {
        let rates = modes.filter { $0.size == size && $0.isHiDPI == hiDPI }.map(\.refreshRate).sorted(by: >)
        return rates.reduce(into: [Double]()) { unique, rate in
            if let last = unique.last, abs(last - rate) < DisplayMode.refreshRateTolerance {
                return
            }
            unique.append(rate)
        }
    }

    /// Prefers the mode at `preferredRate`, otherwise the highest rate; ties broken by the smaller id for determinism.
    static func pick(_ candidates: [DisplayMode], preferredRate: Double?) -> DisplayMode? {
        let ordered = candidates.sorted { ($0.refreshRate, -$0.id) > ($1.refreshRate, -$1.id) }
        if let preferredRate, let match = ordered.first(where: { $0.matchesRefreshRate(preferredRate) }) {
            return match
        }
        return ordered.first
    }
}
