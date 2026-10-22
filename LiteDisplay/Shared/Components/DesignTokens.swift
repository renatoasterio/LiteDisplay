// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import SwiftUI

/// Spacing, radii, sizes and the vibrant palette shared by every screen so the app reads as one system.
enum DesignTokens {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 22
    }

    enum Window {
        static let width: CGFloat = 980
        static let height: CGFloat = 660
        static let minWidth: CGFloat = 840
        static let minHeight: CGFloat = 560
        static let sidebarWidth: CGFloat = 240
    }

    enum MenuBar {
        static let width: CGFloat = 340
    }

    /// Accent gradient for heroes, primary buttons and selection.
    static let brandGradient = LinearGradient(
        colors: [.brandIndigo, .brandViolet, .brandCyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Warmer gradient for the monitor hero card.
    static let heroGradient = LinearGradient(
        colors: [.brandIndigo, .brandViolet, .brandPink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func color(for method: SharpnessMethod) -> Color {
        switch method {
        case .standard: .statusLowRes
        case .hiDPI: .statusHiDPI
        case .virtualDisplay: .statusVirtual
        }
    }

    static func color(for profileColor: ProfileColor) -> Color {
        switch profileColor {
        case .indigo: .brandIndigo
        case .violet: .brandViolet
        case .cyan: .brandCyan
        case .pink: .brandPink
        case .mint: .statusHiDPI
        case .amber: .statusLowRes
        }
    }
}
