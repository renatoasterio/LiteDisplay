// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// Shows which sharpness method a display is using.
struct StatusBadge: View {
    let method: SharpnessMethod
    var onLight = false

    var body: some View {
        Chip(text: method.title, systemImage: method.symbolName, tint: DesignTokens.color(for: method), onLight: onLight)
            .accessibilityLabel(Text("Método: \(method.title)"))
    }
}
