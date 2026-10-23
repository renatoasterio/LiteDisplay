# LiteDisplay

Texto nítido em monitores Full HD conectados a Macs Apple Silicon.

O macOS trata um monitor 1920×1080 como tela 1x e, desde o Mojave, não faz antialiasing subpixel em telas
não-Retina: o resultado é texto serrilhado. O LiteDisplay resolve isso de três formas, escolhidas por monitor:

| Método | Como funciona | Quando usar |
|---|---|---|
| **HiDPI nativo** | Troca o monitor para um modo HiDPI ("parece 1904×1071", desenhado em 3808×2142) oferecido pelo painel ou por um perfil instalado. Mantém a taxa de atualização (até 240 Hz). Persiste sem o app aberto. | Padrão. |
| **Perfil HiDPI** | Quando o macOS não oferece modos HiDPI, o app gera e instala um override em `/Library/Displays/Contents/Resources/Overrides` (pede senha de administrador; reconecte o monitor depois). | Uma vez por monitor. |
| **Tela virtual** | Cria uma tela virtual 2x (ex.: 3840×2160) e espelha o monitor nela: redução exata 2:1, o texto mais nítido possível. Desfeito ao sair do app. | Para comparar, ou quando o perfil não é possível. |

Mais: tamanhos de interface curados (Padrão, Maior, Muito maior, Enorme), taxa de atualização, tabela completa de
modos, **perfis** aplicáveis em um clique (pela janela ou pelo menu) com "aplicar ao conectar", **conforto visual**
(redução de luz azul por temperatura de cor, por monitor ou em todas as telas, com horário), suavização de fontes
mais forte, iniciar no login, restauração automática ao reconectar. Interface em português (Brasil) e inglês.

## Requisitos

macOS 15 ou mais recente, Apple Silicon. Sem rede, sem telemetria.

## Build

```bash
brew install xcodegen swiftlint swiftformat   # ferramentas
make run                                      # gera o projeto, compila (ad-hoc) e abre o app
make test                                     # testes
make audit                                    # auditoria de código (lint, analyzer, verificações de segurança)
make install                                  # copia para /Applications (necessário para "Iniciar no login")
```

O app é assinado ad-hoc: no primeiro lançamento use clique direito › Abrir.

## Diagnóstico

```bash
make modes                 # lista todos os modos de cada monitor, com o atual marcado
scripts/verify-override.sh 472 746   # valida o perfil HiDPI instalado (vendor/product em hex)
```

## Licença

PolyForm Noncommercial License 1.0.0 — veja `LICENSE`.
