// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreFoundation
import Foundation

/// Global grayscale text smoothing. `AppleFontSmoothing` 3 is the strongest weight, 2 the system default;
/// `CGFontRenderingFontSmoothingDisabled` must be false for the weight to matter on recent macOS.
@MainActor
final class FontSmoothingService: FontSmoothingControlling {
    private static let smoothingKey = "AppleFontSmoothing" as CFString
    private static let disabledKey = "CGFontRenderingFontSmoothingDisabled" as CFString
    private static let strong = 3
    private static let regular = 2

    func isStrongSmoothingEnabled() -> Bool {
        let value = CFPreferencesCopyValue(
            Self.smoothingKey,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        return (value as? NSNumber)?.intValue == Self.strong
    }

    func setStrongSmoothing(_ enabled: Bool) throws(LiteDisplayError) {
        let weight = NSNumber(value: enabled ? Self.strong : Self.regular)
        CFPreferencesSetValue(Self.smoothingKey, weight, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSetValue(
            Self.disabledKey,
            kCFBooleanFalse,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        let hostSynced = CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        let anySynced = CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard hostSynced, anySynced else { throw .preferencesFailed }
        Log.system.info("Font smoothing weight set to \(weight)")
    }
}
