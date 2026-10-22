// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// Curated "looks like" sizes as selectable cards.
struct ResolutionGrid: View {
    let sizes: [CuratedSize]
    let selected: DisplaySize?
    let onSelect: (DisplaySize) -> Void

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: DesignTokens.Spacing.md)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.md) {
            ForEach(sizes) { entry in
                SizeCard(entry: entry, isSelected: entry.size == selected) { onSelect(entry.size) }
            }
        }
    }
}

private struct SizeCard: View {
    let entry: CuratedSize
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack {
                    Text(entry.tier.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                    Spacer()
                    if entry.tier == .standard {
                        Chip(text: String(localized: "Recomendado"), tint: .statusHiDPI, onLight: isSelected)
                    }
                }
                Text(entry.size.description)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Text("\(entry.size.doubled.description) px")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignTokens.Spacing.md)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                        .fill(DesignTokens.brandGradient)
                }
            }
            .glassSurface(in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(entry.tier.title), \(entry.size.description)"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
