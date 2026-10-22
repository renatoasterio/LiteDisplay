// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// Primary call to action: white text on the brand gradient.
struct VibrantButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm + 2)
            .background(DesignTokens.brandGradient, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Secondary action: tinted pill.
struct PillButtonStyle: ButtonStyle {
    var tint: Color = .brandIndigo
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(tint.opacity(configuration.isPressed ? 0.26 : 0.14), in: Capsule())
            .opacity(isEnabled ? 1 : 0.45)
    }
}

extension ButtonStyle where Self == VibrantButtonStyle {
    static var vibrant: VibrantButtonStyle {
        VibrantButtonStyle()
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle {
        PillButtonStyle()
    }

    static func pill(_ tint: Color) -> PillButtonStyle {
        PillButtonStyle(tint: tint)
    }
}
