# Contributing to LiteDisplay

Thanks for taking the time to help. Issues and pull requests are welcome in English or Portuguese.

## Ways to help

- **Report your monitor.** The most useful contribution right now: open a
  [compatibility report](../../issues/new?template=compatibility_report.yml) saying which monitor and Mac you use
  and which methods worked.
- **Report a bug** with the [bug report](../../issues/new?template=bug_report.yml) form. The output of `make modes`
  is almost always what is needed to diagnose a display problem.
- **Suggest a feature** with the [feature request](../../issues/new?template=feature_request.yml) form.
- **Translate.** UI strings live in `LiteDisplay/Resources/Localizable.xcstrings`.
- **Send code.** Read the rest of this page first.

## Setup

Requirements: macOS 15 or later, Apple Silicon, Xcode 26.

```bash
brew install xcodegen swiftlint swiftformat
```

```bash
make run
```

| Command | What it does |
|---|---|
| `make generate` | Regenerates `LiteDisplay.xcodeproj` from `project.yml` (the source of truth). |
| `make build` | Debug build into `$TMPDIR/LiteDisplay-DerivedData`. |
| `make test` | Swift Testing suites: Domain, use cases, stores, view models. |
| `make lint` | `swiftlint --strict` and `swiftformat --lint`. |
| `make format` | Applies SwiftFormat. |
| `make audit` | Lint, static analyzer and safety scans. |
| `make modes` | Dumps every display and mode, with the current one marked. |

Build products must stay **outside** the repository folder. Never pass a `-derivedDataPath` that points inside it.

## Architecture in one minute

```
Features ──▶ Domain ◀── Infrastructure
```

- `Domain` — models, protocols and use cases. Imports `Foundation` only.
- `Infrastructure` — one folder per system area (`CoreGraphics`, `VirtualDisplay`, `Override`, `System`, `Storage`).
- `Features` — SwiftUI views and `@MainActor @Observable` view models that depend on Domain protocols only.
- `Shared` — design tokens and reusable components. `App` — entry point and composition root.

Details, including how each sharpness method works: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Rules that are not negotiable

These protect users' machines. A pull request that breaks one will not be merged.

1. **Privilege.** Only `Infrastructure/Override/PrivilegedRunner.swift` spawns a process, only through the standard
   administrator prompt, only after a user click, never at launch. No `sudo`, no persistent helper.
2. **No networking, no telemetry, no dynamic code loading, no third-party dependencies.**
3. **Display changes are transactions.** `CGBeginDisplayConfiguration` → configure →
   `CGCompleteDisplayConfiguration`, with `CGCancelDisplayConfiguration` on every error path, and the result
   verified afterwards. `CGDisplaySetDisplayMode` is forbidden.
4. **Virtual displays** are owned by `VirtualDisplayService` alone.
5. **Gamma tables** are touched by `DisplayGammaService` alone, and always restored at exit.
6. **Swift 6 strict concurrency.** UI and display objects stay on `@MainActor`; C callbacks are top-level functions
   without captures.
7. **Memory.** `[weak self]` in escaping closures, tasks stored and cancelled, observers removed.
8. **Errors.** Typed `LiteDisplayError` with a `recoverySuggestion`. Never `try!`, `as!` or `!` outside tests. Every
   failure a user can hit reaches an inline banner.
9. **Logging.** `Log.<category>` with `privacy: .private` for paths and display names. No `print`.
10. **Localization.** Every user-facing string uses the Portuguese (Brazil) text as its key and has an English
    translation in `Localizable.xcstrings`.

The full list, with the reasoning, is in [CLAUDE.md](CLAUDE.md), the working agreement shared by human and AI
contributors.

## Style

- SwiftFormat and SwiftLint configurations are authoritative; run `make format` and `make lint`.
- Code, comments and documentation are written in English. The UI source language is Portuguese (Brazil).
- Doc comments explain *why*, not *what*.
- Keep files under 500 lines and functions under 60.

## Tests

- Domain, use cases, stores and view models are covered with Swift Testing, using the fakes in
  `LiteDisplayTests/Fakes`. New logic in those layers needs tests.
- Infrastructure talks to real hardware and is verified manually. Follow the checklist in
  [docs/ARCHITECTURE.md → Verification](docs/ARCHITECTURE.md#verification-manual-infrastructure) and say in the pull
  request which steps you ran and on which monitor.

## Sending a pull request

1. Open an issue first for anything larger than a small fix, so the approach can be agreed before you write code.
2. Branch from `main`.
3. Make sure `make test`, `make lint` and `make audit` pass.
4. Fill in the pull request template, including what you verified by hand.
5. Keep the change focused: one topic per pull request.

## License of contributions

LiteDisplay is distributed under the [PolyForm Noncommercial License 1.0.0](LICENSE). By submitting a contribution
you agree that it is licensed under the same terms.
