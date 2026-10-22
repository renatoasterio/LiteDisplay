---
name: code-audit
description: Audits LiteDisplay's Swift code for memory leaks, security weaknesses, privilege and permission misuse, display-API misuse (CoreGraphics transactions, the private virtual display, /Library/Displays overrides) and Swift 6 concurrency mistakes, then reports findings by severity with file:line and a proposed fix (or applies the fixes with --fix). Use at the end of every milestone, before commits that touch Infrastructure, when reviewing a pull request, or whenever someone asks to check code quality, leaks, security or permissions.
---

# LiteDisplay code audit

You are auditing a native macOS menu-bar + window app (Swift 6 strict concurrency, SwiftUI, macOS 15+) that makes a non-Retina external monitor sharp by switching HiDPI modes, mirroring the panel onto a private 2x virtual display, or installing a display override as root. The non-negotiable rules are encoded in the `custom_rules` block of `.swiftlint.yml` and in the reference files of this skill; `CLAUDE.md` holds the architecture when it exists. The dependency rule is Features → Domain ← Infrastructure, with `LiteDisplay/App/AppContainer.swift` as the composition root:

- `LiteDisplay/Domain/{Models,Protocols,UseCases}` — Foundation only. `ModeSelection` (pure algorithms), `HiDPIOverrideProfile` (override bytes), `LiteDisplayError` (typed errors with recovery suggestions).
- `LiteDisplay/Infrastructure/CoreGraphics` — `DisplayEnumerator`, `DisplayModeCatalog`, `DisplayModeService` (Begin/Configure/Complete `.permanently`), `DisplayReconfigurationObserver` (C callback → `AsyncStream`).
- `LiteDisplay/Infrastructure/VirtualDisplay` — `CGVirtualDisplay.h` (private classes, `weak_import`) and `VirtualDisplayService`, the only owner of `CGVirtualDisplay` objects.
- `LiteDisplay/Infrastructure/Override` — `PrivilegedRunner` (the only process spawn: `osascript … with administrator privileges`) and `HiDPIOverrideInstaller`.
- `LiteDisplay/Infrastructure/System` — `FontSmoothingService` (the only `CFPreferences` caller), `LaunchAtLoginService`, `SleepWakeObserver`.
- `LiteDisplay/Infrastructure/Storage` — `SettingsStore` (UserDefaults JSON), `ProfileStore` (atomic JSON in Application Support).
- `LiteDisplay/Features/**` — SwiftUI views and `@MainActor @Observable` view models; `LiteDisplay/Shared/**` components and extensions; `LiteDisplay/App` container, delegate, `Logging.swift`.

Arguments: `--changed` limits the audit to files changed since the last commit (default: whole project). `--fix` applies the fixes for High and Medium findings after reporting them. `--quick` skips the Clang static analyzer.

## Procedure

1. **Run the tooling.** From the repository root:
   ```bash
   .claude/skills/code-audit/scripts/audit.sh [--changed] [--quick]
   ```
   It runs SwiftFormat (lint mode), SwiftLint (strict), the Clang static analyzer (build products under `$TMPDIR`, never inside the checkout), project-specific pattern scans, and a check of `Info.plist`, the entitlements, `project.yml` and `CGVirtualDisplay.h`. Lines marked `FAIL` are verdicts; every other line is a *candidate* for manual review.

2. **Review the code against the checklists.** Open each file in scope and apply the rule lists, choosing by layer:
   - `LiteDisplay/Infrastructure/CoreGraphics/**`, `Infrastructure/VirtualDisplay/**` → `references/display-api-rules.md`, `references/memory-rules.md`, `references/swift-concurrency-rules.md`
   - `LiteDisplay/Infrastructure/Override/**` → `references/permissions-rules.md`, `references/security-rules.md`
   - `LiteDisplay/Infrastructure/System/**` → `references/permissions-rules.md` (global preferences, login item), `references/memory-rules.md` (observer lifetime)
   - `LiteDisplay/Infrastructure/Storage/**` → `references/security-rules.md`
   - `LiteDisplay/Features/**`, `LiteDisplay/App/**` → `references/memory-rules.md` (tasks, observers, ownership), `references/swift-concurrency-rules.md` (`@MainActor`, `isApplying` re-entrancy), `references/display-api-rules.md` (sleep/wake, relaunch fallback), `references/permissions-rules.md` (privileged work only behind a click)
   - `LiteDisplay/Domain/**` → `references/swift-concurrency-rules.md` (`Sendable`, framework-free), `references/display-api-rules.md` (`ModeSelection`, `hasUsableHiDPI`, override bytes)
   - `LiteDisplay/Shared/**` → `references/display-api-rules.md` (`CGDisplayMode+DisplayMode.swift` is the only bridge), localization of user-facing strings
   Read the surrounding code before accepting a candidate: a `Task {}` in a SwiftUI button action that captures only the app-lifetime `container`, or a closure whose owner is guaranteed to outlive it (`// lifetime:` comment present), is not a finding.

3. **Classify.** Use the severity guide at the end of each reference file. In short: High = anything that can leave the user's display in a broken state without recovery, privilege escalation outside `PrivilegedRunner` or without a user click, a missing `CGCancelDisplayConfiguration` on an error path, `CGDisplaySetDisplayMode`, a second owner of a `CGVirtualDisplay`, networking/telemetry/dynamic loading, unsafe file writes into `/Library` or Application Support, data races on view-model state; Medium = retain cycles in Features/App, un-cancelled Tasks, missing validation of persisted JSON, privacy leaks in logs, a `LiteDisplayError` case without a recovery suggestion, missing localization (English literals in views, `String(...)` where `String(localized:)` is needed); Low = style, naming, missing doc comments, lint warnings.

4. **Report.** Print a Markdown table sorted High → Medium → Low:

   | Severity | File:line | Rule | Problem | Proposed fix |

   followed by one line per tool section ("SwiftLint: 0 errors, 2 warnings", "Pattern scans: 0 FAIL, 4 candidates", …) and a final verdict: **PASS** when there is no High finding, no lint/format error and no `FAIL` scan, otherwise **FAIL**. Keep each table cell to one sentence. Do not list the same root cause twice.

5. **Fix (only with `--fix`).** Apply High and Medium fixes in place, keeping the architecture rules (never move process spawning out of `PrivilegedRunner`, never give a second type a `CGVirtualDisplay`, never add a dependency). Then rebuild and test, keeping build products outside the repository:
   ```bash
   xcodebuild -project LiteDisplay.xcodeproj -scheme LiteDisplay -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "${TMPDIR}LiteDisplay-DerivedData" CODE_SIGN_IDENTITY=- build
   xcodebuild -project LiteDisplay.xcodeproj -scheme LiteDisplay -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "${TMPDIR}LiteDisplay-DerivedData" CODE_SIGN_IDENTITY=- test
   ```
   Re-run `audit.sh` and report what changed. Low findings are listed, not fixed, unless the fix is a one-liner.

6. **Dynamic verification** (only when the reviewer asks for it and is watching the external monitor). Record the display state, exercise the app, then look for leaks and prove the display came back:
   ```bash
   swift scripts/dump-modes.swift > "${TMPDIR}modes-before.txt"
   open "${TMPDIR}LiteDisplay-DerivedData/Build/Products/Debug/LiteDisplay.app"
   # In the app: toggle "Texto nítido" 10×, enable/disable "Tela virtual" 10×, open/close the main window 10×.
   pid=$(pgrep -x LiteDisplay)
   leaks "$pid" | tail -n 5                                   # expected: 0 leaks for 0 total leaked bytes
   xcrun xctrace record --template Leaks --attach "$pid" --time-limit 30s --output /tmp/leaks.trace
   swift scripts/dump-modes.swift > "${TMPDIR}modes-after.txt" && diff "${TMPDIR}modes-before.txt" "${TMPDIR}modes-after.txt"
   system_profiler SPDisplaysDataType | grep -A3 XB273       # expected after "Tela virtual" off: "Mirror: Off"
   ```
   Expected: zero leaks, the `diff` shows the same CURRENT mode and no extra display, and no `CGVirtualDisplay` instance in the Xcode memory graph once the virtual display is off. Details and the memory-graph checklist are in `references/memory-rules.md`.

## Guard rails

- Never weaken a rule to make a finding disappear; if a rule is wrong for this codebase, say so in the report and propose the change to `.swiftlint.yml` separately.
- Never run the privileged installer ("Habilitar HiDPI neste monitor…") while auditing; the administrator prompt and the write to `/Library/Displays` are user actions only.
- Never change display modes except in the dynamic verification step, and only with the user watching the monitor; `scripts/dump-modes.swift` is read-only and is the only display tool the audit runs by itself.
- The script is read-only; only `--fix` edits files, and only Swift sources. Build products stay under `$TMPDIR` (`-derivedDataPath`), never inside the checkout.
