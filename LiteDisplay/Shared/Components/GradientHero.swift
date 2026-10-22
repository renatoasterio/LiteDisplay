// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// Vibrant header card with a title, subtitle and a row of chips.
struct GradientHero<Accessory: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let accessory: () -> Accessory

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            shape.fill(DesignTokens.heroGradient)
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 260, height: 260)
                .offset(x: 520, y: -120)
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 180, height: 180)
                .offset(x: 380, y: 60)
            HStack(alignment: .top, spacing: DesignTokens.Spacing.xl) {
                MonitorGlyph(size: 64)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.85))
                    accessory()
                        .padding(.top, DesignTokens.Spacing.xs)
                }
                Spacer(minLength: 0)
            }
            .padding(DesignTokens.Spacing.xl)
        }
        .clipShape(shape)
        .shadow(color: Color.brandIndigo.opacity(0.25), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }
}
