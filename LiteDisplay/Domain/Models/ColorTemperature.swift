// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Per-channel gains applied on top of the display's own gamma table.
struct ChannelGains: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    static let neutral = ChannelGains(red: 1, green: 1, blue: 1)
}

/// Black-body white point as RGB gains, normalised so 6500 K is neutral. Uses Tanner Helland's fit of the
/// CIE data, which is what most screen warmers use; the exact tint is a matter of taste, not accuracy.
enum ColorTemperature {
    static func gains(kelvin: Int) -> ChannelGains {
        let raw = rawRGB(kelvin: Double(kelvin))
        let reference = rawRGB(kelvin: Double(BlueLightSettings.maximumKelvin))
        return ChannelGains(
            red: clamp(raw.red / reference.red),
            green: clamp(raw.green / reference.green),
            blue: clamp(raw.blue / reference.blue)
        )
    }

    private static func rawRGB(kelvin: Double) -> (red: Double, green: Double, blue: Double) {
        let temperature = min(max(kelvin, 1000), 40000) / 100
        let red = temperature <= 66 ? 255 : 329.698727446 * pow(temperature - 60, -0.1332047592)
        let green = temperature <= 66
            ? 99.4708025861 * log(temperature) - 161.1195681661
            : 288.1221695283 * pow(temperature - 60, -0.0755148492)
        let blue: Double = if temperature >= 66 {
            255
        } else if temperature <= 19 {
            0
        } else {
            138.5177312231 * log(temperature - 10) - 305.0447927307
        }
        return (clamp255(red), clamp255(green), clamp255(blue))
    }

    private static func clamp255(_ value: Double) -> Double {
        min(max(value, 0), 255)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
