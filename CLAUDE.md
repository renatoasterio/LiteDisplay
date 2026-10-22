# LiteDisplay — working agreement for humans and AI agents

LiteDisplay is a native macOS menu-bar + window app (Swift 6 strict concurrency, SwiftUI, CoreGraphics display
configuration) that makes a non-Retina external monitor sharp: it switches the panel to a HiDPI mode, installs a
HiDPI override when the panel has none, or mirrors the panel onto a 2x virtual display. Minimum macOS 15,
Apple Silicon only, no App Sandbox, hardened runtime on, ad-hoc signed, zero third-party dependencies.

## Commands

```bash
make generate   # regenerate LiteDisplay.xcodeproj from project.yml (source of truth)
make build      # Debug build into $TMPDIR/LiteDisplay-DerivedData (never inside the repo)
make test       # Swift Testing suites (Domain, use cases, stores, view models)
make lint       # swiftlint --strict + swiftformat --lint
make audit      # .claude/skills/code-audit/scripts/audit.sh (lint, analyzer, safety scans)
make run        # build and launch
make modes      # swift scripts/dump-modes.swift — every display and mode, current one marked
make install    # copy to /Applications (stable path for the login item)
```

Run `/code-audit` (project skill) at the end of every milestone and before any commit that touches `Infrastructure`.

Build products must stay outside the repository folder: this checkout may live in a synced folder that stamps
Finder metadata on new bundles and breaks `codesign`. Never pass `-derivedDataPath` pointing inside the repo.

## Architecture (see docs/ARCHITECTURE.md)

- `LiteDisplay/Domain` — models, protocols and use cases. Imports `Foundation` only. Display ids are `UInt32`,
  modes are `DisplayMode` values. The pure rules (`ModeSelection`, `HiDPIOverrideProfile`) are unit-tested.
- `LiteDisplay/Infrastructure` — one folder per system area: `CoreGraphics` (enumeration, mode transactions,
  reconfiguration callbacks), `VirtualDisplay` (private `CGVirtualDisplay` API), `Override` (privileged install),
  `System` (font smoothing, login item, sleep/wake), `Storage` (settings, profiles).
- `LiteDisplay/Features` — SwiftUI views + `@MainActor @Observable` view models per feature (`MainWindow`,
  `Monitors`, `Profiles`, `Settings`, `MenuBar`). View models depend on Domain protocols only.
- `LiteDisplay/Shared` — design tokens, glass surfaces, cards, chips, badges, button styles, extensions.
- `LiteDisplay/App` — entry point, `AppDelegate`, `AppContainer` (composition root), `Log`.
- Dependencies point downwards only: Features → Domain ← Infrastructure. Tests replace Infrastructure with
  `LiteDisplayTests/Fakes`.

## Non-negotiable rules

1. **Privilege**: only `Infrastructure/Override/PrivilegedRunner.swift` spawns a process, only through
   `osascript … with administrator privileges`, only after a user click, never at launch. Commands are built from
   constants and `shellQuoted` paths; vendor/product ids are validated hex. No `sudo`, no persistent helper.
2. **No networking, no telemetry, no dynamic code loading.** The private virtual display classes are declared with
   `weak_import` and used only in `Infrastructure/VirtualDisplay` behind an `NSClassFromString` guard.
3. **Display transactions**: `CGBeginDisplayConfiguration` → configure → `CGCompleteDisplayConfiguration`,
   `CGCancelDisplayConfiguration` on every error path, `.permanently` for panel modes, `.forSession` for virtual
   mirrors, verify after completing. `CGDisplaySetDisplayMode` is forbidden (it reverts at exit). Mode identity is
   `ioDisplayModeID` with a `ModeKey` fallback. Always pass `kCGDisplayShowDuplicateLowResolutionModes`.
4. **Virtual displays**: `VirtualDisplayService` is the only owner of `CGVirtualDisplay` objects; never set a
   `terminationHandler`; only change the virtual mode when needed; tear down before sleep and before quitting.
5. **Memory**: `[weak self]` in escaping closures (or a `// lifetime:` comment), Tasks stored and cancelled,
   reconfiguration callback removed in `deinit`, observers removed in `stop()`/`deinit`.
6. **Concurrency**: Swift 6 strict. UI, `CGDisplayMode` and the private classes stay on `@MainActor`; C callbacks are
   top-level functions without captures; `Process` runs detached and returns only `Sendable` values; no
   `DispatchQueue.main` in Infrastructure.
7. **Errors**: typed `LiteDisplayError` with a `recoverySuggestion`; never `try!`, `as!` or `!` outside tests. Every
   failure the user can hit reaches an inline banner.
8. **Files**: atomic writes, temp files under `temporaryDirectory` with 0700/0600 and deleted in `defer`, persisted
   JSON validated on load, `/Library/Displays` written only by the installer and read back for verification.
9. **Logging**: `Log.<category>` (`os.Logger`), `privacy: .private` for paths and display names. No `print`.
10. **Localization**: every user-facing string goes through SwiftUI `Text`/`String(localized:)` with the Portuguese
    (Brazil) text as the key and an English translation in `Resources/Localizable.xcstrings`.
11. **UI**: Apple HIG, vibrant brand palette from `DesignTokens`, Liquid Glass via `glassSurface` (material fallback on
    macOS 15), system fonts, SF Symbols, accessibility labels on every control.
12. **Tests**: Swift Testing for Domain, use cases, stores and view models using `LiteDisplayTests/Fakes`.
    Infrastructure is verified manually (docs/ARCHITECTURE.md → Verification).

## Style

SwiftFormat and SwiftLint configs are authoritative (`.swiftformat`, `.swiftlint.yml`; SwiftFormat takes paths before
options: `swiftformat LiteDisplay LiteDisplayTests --lint`). Doc comments explain *why*. Keep files under 500 lines and
functions under 60. Code, comments and docs are written in English; the UI source language is Portuguese (Brazil).
