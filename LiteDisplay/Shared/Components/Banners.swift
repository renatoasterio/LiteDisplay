// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// Inline error with its recovery suggestion.
struct ErrorBanner: View {
    let error: LiteDisplayError
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.statusError)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.errorDescription ?? String(localized: "Algo deu errado."))
                    .font(.callout.weight(.semibold))
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let onDismiss {
                Button("Fechar", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(Color.statusError.opacity(0.12), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Inline confirmation or hint.
struct NoticeBanner: View {
    let text: String
    var tint: Color = .statusHiDPI
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(tint)
            Text(text)
                .font(.callout)
            Spacer(minLength: 0)
            if let onDismiss {
                Button("Fechar", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
