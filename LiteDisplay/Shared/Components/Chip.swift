// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// A small tinted capsule for facts such as "120 Hz" or "HiDPI".
struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary
    var onLight = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, DesignTokens.Spacing.sm + 2)
        .padding(.vertical, DesignTokens.Spacing.xs + 1)
        .foregroundStyle(onLight ? Color.white : tint)
        .background(onLight ? Color.white.opacity(0.22) : tint.opacity(0.16), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A chip the user can pick, drawn with the brand gradient when selected.
struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background {
                    if isSelected {
                        Capsule().fill(DesignTokens.brandGradient)
                    } else {
                        Capsule().fill(.quaternary.opacity(0.6))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
