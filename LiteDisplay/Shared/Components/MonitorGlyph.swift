// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// A stylised monitor drawn with shapes so it scales crisply at any size.
struct MonitorGlyph: View {
    var size: CGFloat = 48
    var tint: Color = .white

    var body: some View {
        VStack(spacing: size * 0.05) {
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .fill(tint.opacity(0.22))
                .overlay(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous).stroke(tint, lineWidth: max(2, size * 0.04)))
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: size * 0.28, weight: .bold))
                        .foregroundStyle(tint)
                )
                .frame(width: size, height: size * 0.62)
            RoundedRectangle(cornerRadius: size * 0.03)
                .fill(tint)
                .frame(width: size * 0.12, height: size * 0.12)
            Capsule()
                .fill(tint)
                .frame(width: size * 0.5, height: size * 0.07)
        }
        .accessibilityHidden(true)
    }
}
