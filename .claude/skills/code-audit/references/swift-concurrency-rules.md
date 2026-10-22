# Swift concurrency rules — LiteDisplay code audit

**Scope.** Swift 6 language mode with `SWIFT_STRICT_CONCURRENCY = complete`, so most data races are compile errors; this checklist targets what still compiles and is wrong. LiteDisplay's isolation story is deliberately simple: almost everything is `@MainActor`, because `CGDisplayMode`, `CGDisplayConfigRef` and the private `CGVirtualDisplay*` classes are not `Sendable`, the window server serialises transactions anyway, and SwiftUI reads the view models on main. The exceptions are small and must stay small: `DisplayReconfigurationObserver` (`Sendable`, called by the window server on an arbitrary thread, yields into an `AsyncStream`), `PrivilegedRunner` (a `Sendable` struct that runs the blocking `osascript` in `Task.detached`), `HiDPIOverrideInstaller` (stateless struct) and the Domain value types. Errors are typed (`throws(LiteDisplayError)`). The re-entrancy guard for display work is `MonitorsViewModel.isApplying`.

## 1. **Services that touch CoreGraphics configuration or the private classes are `@MainActor`, and their protocols are `@MainActor protocol … : AnyObject`**

`DisplayModeService`, `VirtualDisplayService`, `DisplayEnumerator` and `DisplayModeCatalog` hold or return non-`Sendable` framework objects. Making one of them an `actor` or `nonisolated` forces those objects across an isolation boundary, which the compiler then rejects and someone "fixes" with `@unchecked Sendable`. The Domain protocols mirror this (`DisplayProviding`, `DisplayModeApplying`, `VirtualDisplayControlling`, `SettingsStoring`, `ProfileStoring`, `FontSmoothingControlling`, `LoginItemControlling` are all `@MainActor`), while the two stateless boundaries (`OverrideInstalling`, `PrivilegedExecuting`) are `Sendable`.

Grep: `final class \w+(Service|Enumerator|Catalog|Store)\b` without `@MainActor` on the line above; `actor \w+` (expect none); `protocol \w+(Providing|Applying|Controlling|Storing)\b` without `@MainActor`.

Wrong:
```swift
actor VirtualDisplayService: VirtualDisplayControlling {
    private var handles: [UInt32: CGVirtualDisplay]        // non-Sendable objects inside an actor; every caller hops and the mirror transaction runs off main
}
```
Right:
```swift
@MainActor protocol VirtualDisplayControlling: AnyObject { … }
@MainActor final class VirtualDisplayService: VirtualDisplayControlling { private var handles: [UInt32: Handle] = [:] }
```

## 2. **`CGDisplayMode` and `CGVirtualDisplay*` never leave `@MainActor`; everything above Infrastructure sees `DisplayMode`/`DisplaySnapshot` values**

`CGDisplayMode+DisplayMode.swift` (`domainMode`) is the only bridge; `DisplayModeCatalog.usableModes` returns `[DisplayMode]`, `currentMode(of:)` returns `DisplayMode?`, and the only function returning a `CGDisplayMode` (`cgMode(matching:on:)`) is called by the two services inside their transactions. A `DisplaySnapshot` field, a use-case parameter or a `Task` capture of a `CGDisplayMode` is a finding even if it compiles.

Grep: `CGDisplayMode` outside `Infrastructure/CoreGraphics/`, `Infrastructure/VirtualDisplay/` and `Shared/Extensions/CGDisplayMode+DisplayMode.swift`; `: CGDisplayMode|\[CGDisplayMode\]` in `Domain/|Features/`.

Wrong:
```swift
struct DisplaySnapshot { let cgModes: [CGDisplayMode] }                    // not Sendable; leaks framework types into Domain
```
Right:
```swift
struct DisplaySnapshot: Identifiable, Hashable, Sendable { let currentMode: DisplayMode?; let modes: [DisplayMode] }
static func cgMode(matching mode: DisplayMode, on displayID: CGDirectDisplayID) -> CGDisplayMode?   // @MainActor, Infrastructure-internal
```

## 3. **View models are `@MainActor @Observable`; `isApplying` is the single re-entrancy guard and every display action goes through `perform`**

Two overlapping transactions (`CGBeginDisplayConfiguration` while another is pending) fail or interleave, and the second `refresh()` reads a half-applied state. `MonitorsViewModel.perform` sets `isApplying`, clears messages, awaits the work, catches the typed error, clears `isApplying` in `defer` and refreshes; `handle(_:)` and `reapplyIfNeeded` check the same flag; `ProfilesViewModel.apply` has its own. A new action that calls a use case directly, or a view that reads `isApplying` but launches work anyway, bypasses the guard.

Grep: `sharpness\.execute|resolution\.execute|overrideInstaller\.execute|reapply\.execute` outside `perform \{|reapplyIfNeeded`; `@Observable` without `@MainActor` on the line above; `isApplying = true` without a matching `defer { isApplying = false }`.

Wrong:
```swift
func setSize(_ size: DisplaySize, for display: DisplaySnapshot) async {
    try? await resolution.execute(display: display, size: size)       // no guard, no error surfaced, no refresh
}
```
Right:
```swift
func setSize(_ size: DisplaySize, for display: DisplaySnapshot) async {
    await perform { () async throws(LiteDisplayError) in try await resolution.execute(display: display, size: size) }
}
private func perform(_ work: () async throws(LiteDisplayError) -> Void) async {
    guard !isApplying else { return }
    isApplying = true; error = nil; notice = nil
    defer { isApplying = false }
    do { try await work() } catch { self.error = error; Log.ui.error("Display action failed: \(error.localizedDescription, privacy: .public)") }
    refresh()
}
```

## 4. **The reconfiguration callback is a capture-free top-level function on a `Sendable` observer that only yields; the hop to main happens in the consumer**

The window server invokes the callback on whichever thread triggered the change: the main thread for the app's own transaction, a system thread for a cable plug. `DisplayReconfigurationObserver` is `final class … : Sendable` with `let` properties only; `handle` touches nothing but the continuation. `MainActor.assumeIsolated` there would trap on the first real plug; a `DispatchQueue.main.async` would hide the isolation from the compiler.

Grep: `assumeIsolated|DispatchQueue\.main|MainActor\.run` in `DisplayReconfigurationObserver.swift` (expect none); `var ` stored properties in that class; the callback declared as a closure instead of `private func`.

Wrong:
```swift
private func displayReconfigurationCallback(_ id: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ userInfo: UnsafeMutableRawPointer?) {
    MainActor.assumeIsolated { viewModel.refresh() }                   // traps when the window server calls from its own thread
}
```
Right:
```swift
fileprivate func handle(_ displayID: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags) {
    guard !flags.contains(.beginConfigurationFlag) else { return }
    continuation.yield(flags.contains(.addFlag) ? .added(displayID) : flags.contains(.removeFlag) ? .removed(displayID) : .reconfigured(displayID))
}
// MonitorsViewModel (main actor): for await change in stream { handle(change) }
```

## 5. **No `DispatchQueue.main` in Infrastructure; results come back through `async throws(LiteDisplayError)` functions or the `AsyncStream`**

Infrastructure should not know where its consumer lives. A main-queue hop inside a service bypasses actor checking, hides ordering and makes the service untestable with the fakes in `LiteDisplayTests/Fakes`. The `.swiftlint.yml` rule `no_main_hop_in_infrastructure` makes this an error; the audit script scans for it as well.

Grep: `DispatchQueue\.main|MainActor\.run|RunLoop\.main|performSelector\(onMainThread` under `Infrastructure/` (expect zero).

Wrong:
```swift
func activate(for display: DisplaySnapshot, completion: @escaping (LiteDisplayError?) -> Void) {
    queue.async { … DispatchQueue.main.async { completion(nil) } }     // isolation invisible to the compiler
}
```
Right:
```swift
func activate(for display: DisplaySnapshot) async throws(LiteDisplayError)   // @MainActor; awaits Task.sleep while polling
```

## 6. **Blocking calls (`waitUntilExit`, `readDataToEndOfFile`) live only inside `PrivilegedRunner.execute` under `Task.detached`; polling uses `Task.sleep`**

The administrator dialog blocks the calling thread for as long as the user takes; on main that freezes the menu bar extra and every window. `PrivilegedRunner.run` awaits `Task.detached(priority: .userInitiated) { Self.execute(script) }.value`, which returns a `Sendable` `Outcome`. `VirtualDisplayService.waitUntilOnline/waitUntilRemoved` poll `CGDisplayIsOnline` with `try? await Task.sleep(for: .milliseconds(50))` against a `ContinuousClock` deadline, so the main actor stays responsive. `DispatchSemaphore`, `DispatchGroup.wait`, `Thread.sleep`, `usleep`, `RunLoop.run` and `queue.sync` have no place in the app.

Grep: `DispatchSemaphore|\.wait\(|DispatchGroup\(\)|Thread\.sleep|usleep\(|\bsleep\(|RunLoop\.(main|current)\.run|\.sync \{`; `waitUntilExit|readDataToEndOfFile` outside `PrivilegedRunner.swift`; `Task\.detached` outside `PrivilegedRunner.swift`.

Wrong:
```swift
func run(_ command: String, prompt: String) throws(LiteDisplayError) {
    let process = Process(); …; try? process.run(); process.waitUntilExit()   // main actor blocked behind the password dialog
}
while CGDisplayIsOnline(virtualID) == 0 { usleep(50_000) }                    // blocks main; the window server may need main to finish
```
Right:
```swift
let outcome = await Task.detached(priority: .userInitiated) { Self.execute(script) }.value   // Outcome: Sendable
while CGDisplayIsOnline(virtualID) == 0 {
    guard ContinuousClock.now < deadline else { throw .virtualDisplayFailed("timeout") }
    try? await Task.sleep(for: Self.pollInterval)
}
```

## 7. **Tasks that outlive a call re-check `self` and cancellation after every `await` and re-read live state instead of a pre-await snapshot**

Between an `await` and the next line a display can be unplugged, the virtual display released, or the view model stopped. `pendingRefresh`, `observation` and `wakeTask` all capture `[weak self]`, `guard let self, !Task.isCancelled` after the sleep, and then call `displays.externalDisplays()` / `refresh()` again rather than acting on the `DisplaySnapshot` captured before the wait. `resumeVirtualDisplays` keeps only `persistentID`s across the wait for the same reason.

Grep: `Task\.sleep` not followed by `guard let self|Task\.isCancelled` within three lines; `for display in` over a snapshot array captured before an `await` in the same function; `for await` bodies without `Task.isCancelled`.

Wrong:
```swift
let active = displays.externalDisplays()                 // snapshot before the wait
wakeTask = Task { try? await Task.sleep(for: .seconds(2)); for d in active { try? await sharpness.execute(.init(display: d, method: .virtualDisplay)) } }
```
Right:
```swift
suspendedVirtualDisplays = active.map(\.persistentID)    // ids survive a reconnection; snapshots do not
wakeTask = Task { [weak self] in
    try? await Task.sleep(for: .seconds(2))
    guard let self, !Task.isCancelled else { return }
    let pending = suspendedVirtualDisplays; suspendedVirtualDisplays = []
    for display in displays.externalDisplays() where pending.contains(display.persistentID) { … }
}
```

## 8. **The reconfiguration `AsyncStream` has one consumer, is finished in `deinit`, and `.unbounded` is acceptable only because events are rare and debounced**

`DisplayProviding.changes` documents "one subscriber only": a second `for await` on the same stream splits events between consumers at random. `.unbounded` is fine for a stream that carries a handful of events per reconfiguration into a 1.5 s debounce; a stream fed per tick or per frame would need `.bufferingNewest(1)`. `continuation.finish()` in `deinit` lets the consumer loop end when the observer goes away.

Grep: `provider\.changes|\.changes` consumers (expect `MonitorsViewModel.start` only); `AsyncStream\.makeStream` and `bufferingPolicy`; `continuation\.finish\(\)` in the observer's `deinit`.

Wrong:
```swift
// ProfilesViewModel
Task { for await _ in provider.changes { reload() } }     // second consumer: MonitorsViewModel now misses half the events
```
Right:
```swift
/// One subscriber only: the stream is consumed by the monitors view model.
var changes: AsyncStream<DisplayChange> { get }
profiles.displaysDidChange = { [weak self] in self?.monitors.refresh() }   // other screens are told by the view model
```

## 9. **`Task.detached` only for the blocking subprocess, returning a `Sendable` value; `Task { @MainActor in }` for the two AppKit callbacks that need main**

`Task {}` inherits the main actor from the view models and the container, which is what display work needs. `Task.detached` drops isolation and priority: fine for `osascript`, wrong for anything that touches CoreGraphics configuration, the private classes or view-model state. `NSWorkspace.openApplication`'s completion and `applicationShouldTerminate` use `Task { @MainActor in … }` to get back to main explicitly.

Grep: `Task\.detached` (expect one, in `PrivilegedRunner.run`); `Task\.detached` whose body mentions `CG|handles|displays|error =|notice =`.

Wrong:
```swift
Task.detached { try? await self.virtualDisplays.activate(for: display) }   // main-actor method hopped from a detached context; priority lost
```
Right:
```swift
NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
    if let error { Log.app.error("Relaunch failed: \(error.localizedDescription, privacy: .public)"); return }
    Task { @MainActor in NSApp.terminate(nil) }
}
```

## 10. **Typed throws end to end: `throws(LiteDisplayError)` on protocols, use cases and `perform` closures; framework errors are wrapped at the boundary; no `try!`, no `try?` that hides a recoverable error**

The view models store `LiteDisplayError` so `ErrorBanner` can show `recoverySuggestion`. A function declared `throws` (untyped) in the middle of the chain forces `catch` blocks to downcast and loses the typed guarantee; `try?` on `deactivate` hides `virtualDisplayLingering`, which has a dedicated button. Infrastructure wraps (`catch { throw .storageFailed(error.localizedDescription) }`, `loginItemFailed`, `privilegedCommandFailed`).

Grep: `throws\b(?!\(LiteDisplayError\))` in `Domain/Protocols|Domain/UseCases|Infrastructure`; `try!`; `try\? await (sharpness|resolution|virtualDisplays|modes)\.`; `catch \{` in Infrastructure that rethrows `error` untyped.

Wrong:
```swift
func apply(_ mode: DisplayMode, to displayID: UInt32) throws              // untyped; callers get `any Error`
try? await virtualDisplays.deactivate(for: display.id)                     // lingering display reported as success
```
Right:
```swift
func apply(_ mode: DisplayMode, to displayID: UInt32) throws(LiteDisplayError)
await perform { () async throws(LiteDisplayError) in try await sharpness.execute(.init(display: display, method: method)) }
```

## 11. **Domain models are `Sendable` value types; escape hatches (`@unchecked Sendable`, `nonisolated(unsafe)`, `assumeIsolated`, `@preconcurrency`) appear only in test fakes, each with a comment**

`DisplaySnapshot`, `DisplayMode`, `DisplaySettings`, `Profile`, `AppSettings`, `HiDPIOverrideProfile`, `LiteDisplayError` and `SetSharpnessUseCase.Request` are `Sendable` structs/enums and cross from views to use cases on every action. The app target has no `@unchecked Sendable`; the two in `LiteDisplayTests/Fakes/Fakes.swift` (`FakeOverrideInstaller`, `FakePrivilegedExecutor`) carry "Test-only; state is touched from one test at a time". The closures `SleepWakeObserver` stores are `@MainActor @Sendable`.

Grep: `@unchecked Sendable|nonisolated\(unsafe\)|assumeIsolated|assertIsolated|@preconcurrency` in `LiteDisplay/` (expect none); `^\s*(struct|enum) \w+` in `Domain/Models` without `Sendable`; `@escaping` closures stored in `@MainActor` classes without `@MainActor @Sendable`.

Wrong:
```swift
final class VirtualDisplayService: @unchecked Sendable { var handles: [UInt32: Handle] = [:] }   // silences the compiler, keeps the race
```
Right:
```swift
struct Request: Sendable { let display: DisplaySnapshot; let method: SharpnessMethod; var size: DisplaySize?; var refreshRate: Double? }
private let onSleep: @MainActor @Sendable () -> Void
```

## 12. **`deinit` does only nonisolated work; main-actor cleanup lives in `stop()`/`shutdown()` called from `applicationShouldTerminate`**

In Swift 6 a `@MainActor` class's `deinit` is not isolated and cannot call its own isolated methods or safely read isolated `var`s. `SleepWakeObserver.deinit` calls only `removeObserver(self)`; `DisplayReconfigurationObserver` is non-isolated by design; `MonitorsViewModel` cancels its tasks in `stop()`, which `AppContainer.shutdown()` calls before `deactivateAll()`. A `deinit { observation?.cancel() }` on a view model, or `deinit { handles.removeAll() }` on the service, either fails to compile or runs on the wrong actor.

Grep: `deinit` in `@MainActor` classes — body must be `removeObserver(self)` or empty; `shutdown\(\)` ordering: `monitors.stop()`, `sleepWake?.stop()`, `wakeTask?.cancel()`, then `virtualDisplays.releaseAll()` — all synchronous, because it runs inside `applicationShouldTerminate` (memory rule 11).

Wrong:
```swift
@MainActor final class MonitorsViewModel {
    deinit { observation?.cancel(); pendingRefresh?.cancel() }   // isolated state from a nonisolated deinit
}
```
Right:
```swift
func stop() { observation?.cancel(); observation = nil; pendingRefresh?.cancel(); pendingRefresh = nil }
func shutdown() { monitors.stop(); sleepWake?.stop(); wakeTask?.cancel(); virtualDisplays.releaseAll() }
```

## Severity guide

| Severity | Classify here when… | Typical findings from this file |
|---|---|---|
| High | A real data race, a trap on a system thread, a frozen main actor, or two display transactions that can interleave | `@unchecked Sendable`/`nonisolated(unsafe)` in the app target (#11); `assumeIsolated` or `DispatchQueue.main` in the reconfiguration callback (#4, #5); `waitUntilExit`/`usleep`/semaphore on the main actor (#6); display action bypassing `perform`/`isApplying` (#3); `CGDisplayMode` or `CGVirtualDisplay` crossing out of `@MainActor` (#2); a second consumer of `changes` (#8) |
| Medium | Isolation is wrong but currently masked, or work outlives its owner | Service or protocol missing `@MainActor` (#1); `Task.detached` for non-subprocess work (#9); snapshot used after an `await` without re-reading (#7); untyped `throws` in the chain or `try?` hiding `virtualDisplayLingering` (#10); isolated cleanup in `deinit` (#12); `.unbounded` on a stream fed more often than reconfiguration events (#8) |
| Low | Correct but undocumented or stylistic | `@unchecked Sendable` in a fake without the comment (#11); redundant `nonisolated`; `Task { @MainActor in }` where the caller is already on main (#9) |
