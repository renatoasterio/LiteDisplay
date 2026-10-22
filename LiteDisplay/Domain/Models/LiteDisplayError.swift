// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Every failure the user can hit, with a recovery suggestion.
enum LiteDisplayError: Error, Hashable, Sendable {
    case displayNotFound
    case modeUnavailable
    case hiDPIUnavailable
    case controlledByVirtualDisplay
    case configurationFailed(stage: String, code: Int32)
    case verificationFailed
    case virtualDisplayUnavailable
    case virtualDisplayFailed(String)
    case virtualDisplayLingering
    case privilegeDenied
    case privilegedCommandFailed(String)
    case overrideVerificationFailed(String)
    case invalidIdentifier
    case loginItemFailed(String)
    case storageFailed(String)
    case preferencesFailed
}

extension LiteDisplayError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .displayNotFound:
            String(localized: "O monitor não está mais conectado.")
        case .modeUnavailable:
            String(localized: "Esse modo não está disponível neste monitor.")
        case .hiDPIUnavailable:
            String(localized: "Este monitor não oferece modos HiDPI.")
        case .controlledByVirtualDisplay:
            String(localized: "A resolução está sendo controlada pela tela virtual.")
        case let .configurationFailed(stage, code):
            String(localized: "O macOS recusou a mudança de modo (\(stage), código \(code)).")
        case .verificationFailed:
            String(localized: "O monitor não ficou no modo pedido.")
        case .virtualDisplayUnavailable:
            String(localized: "Esta versão do macOS não permite criar telas virtuais.")
        case let .virtualDisplayFailed(detail):
            String(localized: "Não foi possível criar a tela virtual (\(detail)).")
        case .virtualDisplayLingering:
            String(localized: "A tela virtual continua ativa.")
        case .privilegeDenied:
            String(localized: "A instalação foi cancelada.")
        case let .privilegedCommandFailed(detail):
            String(localized: "A instalação do perfil falhou: \(detail)")
        case let .overrideVerificationFailed(detail):
            String(localized: "O perfil instalado não confere: \(detail)")
        case .invalidIdentifier:
            String(localized: "O identificador do monitor é inválido.")
        case let .loginItemFailed(detail):
            String(localized: "Não foi possível alterar o item de login: \(detail)")
        case let .storageFailed(detail):
            String(localized: "Não foi possível salvar: \(detail)")
        case .preferencesFailed:
            String(localized: "Não foi possível gravar a preferência de suavização.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .displayNotFound:
            String(localized: "Reconecte o cabo e tente novamente.")
        case .modeUnavailable, .verificationFailed:
            String(localized: "Escolha outro tamanho ou taxa de atualização.")
        case .hiDPIUnavailable:
            String(localized: "Use “Habilitar HiDPI neste monitor” ou a tela virtual.")
        case .controlledByVirtualDisplay:
            String(localized: "Desligue a tela virtual para escolher outra resolução.")
        case .configurationFailed:
            String(localized: "Saia de apps em tela cheia e tente de novo.")
        case .virtualDisplayUnavailable:
            String(localized: "Use o modo HiDPI nativo.")
        case .virtualDisplayFailed:
            String(localized: "Tente novamente ou use o modo HiDPI nativo.")
        case .virtualDisplayLingering:
            String(localized: "Reabra o LiteDisplay para removê-la.")
        case .privilegeDenied:
            String(localized: "Clique de novo e informe a senha de administrador.")
        case .privilegedCommandFailed, .overrideVerificationFailed:
            String(localized: "Verifique o espaço em disco e as permissões de /Library/Displays.")
        case .invalidIdentifier:
            String(localized: "Este monitor não pode receber um perfil HiDPI.")
        case .loginItemFailed:
            String(localized: "Ative o LiteDisplay em Ajustes do Sistema › Geral › Itens de Login.")
        case .storageFailed:
            String(localized: "Verifique o espaço em disco.")
        case .preferencesFailed:
            String(localized: "Tente novamente.")
        }
    }
}
