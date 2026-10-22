// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Accent used to tell profiles apart at a glance.
enum ProfileColor: String, Codable, Sendable, CaseIterable, Identifiable {
    case indigo, violet, cyan, pink, mint, amber

    var id: String {
        rawValue
    }
}

/// A named set of display configurations the user can apply in one click.
struct Profile: Identifiable, Codable, Sendable, Hashable {
    static let defaultSymbol = "display"
    static let symbolChoices = ["display", "sparkles", "gamecontroller", "briefcase", "moon.stars", "film", "paintpalette", "bolt"]

    var id: UUID
    var name: String
    var color: ProfileColor
    var symbolName: String
    /// Persistent display id → wanted configuration.
    var displays: [String: DisplaySettings]
    /// Re-apply automatically when one of its displays is connected.
    var applyOnConnect: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        color: ProfileColor = .indigo,
        symbolName: String = Profile.defaultSymbol,
        displays: [String: DisplaySettings] = [:],
        applyOnConnect: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.symbolName = symbolName
        self.displays = displays
        self.applyOnConnect = applyOnConnect
        self.createdAt = createdAt
    }

    /// A profile read from disk is only trusted when its fields are sane.
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 60 && !displays.isEmpty
    }
}
