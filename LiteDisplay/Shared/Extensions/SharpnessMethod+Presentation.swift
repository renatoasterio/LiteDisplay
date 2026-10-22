// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

extension SharpnessMethod {
    var title: String {
        switch self {
        case .standard: String(localized: "Padrão (1x)")
        case .hiDPI: String(localized: "HiDPI nativo")
        case .virtualDisplay: String(localized: "Tela virtual")
        }
    }

    var summary: String {
        switch self {
        case .standard:
            String(localized: "O macOS desenha na resolução do painel, sem suavização HiDPI. Texto serrilhado em monitores Full HD.")
        case .hiDPI:
            String(localized: "Desenha em 2x e reduz para o painel usando um modo HiDPI do próprio monitor. Mantém a taxa de atualização.")
        case .virtualDisplay:
            String(localized: "Cria uma tela virtual 2x e espelha o monitor nela: redução exata 2:1, o texto mais nítido possível.")
        }
    }

    var symbolName: String {
        switch self {
        case .standard: "square.grid.3x3"
        case .hiDPI: "sparkles"
        case .virtualDisplay: "rectangle.on.rectangle"
        }
    }
}

extension CuratedSize.Tier {
    var title: String {
        switch self {
        case .moreSpace: String(localized: "Mais espaço")
        case .standard: String(localized: "Padrão")
        case .larger: String(localized: "Maior")
        case .muchLarger: String(localized: "Muito maior")
        case .huge: String(localized: "Enorme")
        case .custom: String(localized: "Personalizado")
        }
    }
}

extension DisplayMode {
    /// "1904×1071 HiDPI @ 120 Hz"
    var summary: String {
        isHiDPI
            ? String(localized: "\(size.description) HiDPI @ \(refreshRate.hertzLabel)")
            : String(localized: "\(size.description) @ \(refreshRate.hertzLabel)")
    }
}

extension DisplaySettings {
    /// One line for profile cards: "HiDPI nativo · 1904×1071 @ 120 Hz".
    var summary: String {
        var parts = [method.title]
        if let size {
            parts.append(size.description)
        }
        if let refreshRate {
            parts.append(refreshRate.hertzLabel)
        }
        return parts.joined(separator: " · ")
    }
}
