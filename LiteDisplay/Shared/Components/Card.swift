// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// A rounded glass panel that groups related controls.
struct Card<Content: View>: View {
    var tint: Color?
    var isHighlighted = false
    @ViewBuilder let content: () -> Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
    }

    var body: some View {
        content()
            .padding(DesignTokens.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(in: shape, tint: tint)
            .overlay {
                if isHighlighted {
                    shape.strokeBorder(DesignTokens.brandGradient, lineWidth: 2)
                }
            }
    }
}
