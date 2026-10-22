# Memory rules — LiteDisplay code audit

**Scope.** Object lifetime in LiteDisplay: the few objects that hold window-server resources (`CGVirtualDisplay` handles in `VirtualDisplayService`, the C callback registered by `DisplayReconfigurationObserver`, a begun `CGDisplayConfigRef`), the long-running `Task`s in `MonitorsViewModel` and `AppContainer`, the selector-based `SleepWakeObserver`, the `Process` and pipes in `PrivilegedRunner`, the staging directory in `HiDPIOverrideInstaller`, and CoreFoundation ownership (`CGDisplayCreateUUIDFromDisplayID`). The app is small and idle most of the time, so a leak rarely shows as memory growth; it shows as a phantom virtual display that survives "Tela virtual" off, a crash on the next cable plug because the window server called into a freed observer, or a view model that keeps reacting after `stop()`. Apply to `Infrastructure/`, `Features/` and `App/`; `Domain/` is value types. Acceptance target: **zero leaks and zero `CGVirtualDisplay` instances after ten on/off cycles of each toggle** (see "How to verify dynamically").

## 1. **Long-running `Task`s are stored, capture `self` weakly, re-check after every `await` and are cancelled in `stop()`**

An unstructured `Task` keeps its strong captures alive until the body returns; `for await change in provider.changes` never returns by itself, so a strong `self` keeps `MonitorsViewModel` (and through the use cases every service) alive forever and a second `start()` doubles the consumers of the one-subscriber stream. SwiftUI `Task {}` blocks in button actions and `Binding` setters capture `container` (app-lifetime) and `display` (a value) and finish quickly; they are fine as long as they go through `perform`, which serialises them with `isApplying`.

Grep: `Task \{` in `Features/|App/` not assigned to a property; `for await` in a type without `cancel\(\)`; `\.onAppear \{[^}]*Task`.

Wrong:
```swift
func start() {
    Task { for await change in provider.changes { handle(change) } }   // strong self, never cancelled, doubles on restart
}
```
Right (`MonitorsViewModel`):
```swift
@ObservationIgnored private var observation: Task<Void, Never>?
func start() {
    refresh()
    observation?.cancel()
    observation = Task { [weak self] in
        guard let stream = self?.provider.changes else { return }
        for await change in stream {
            guard let self, !Task.isCancelled else { return }
            handle(change)
        }
    }
}
func stop() { observation?.cancel(); observation = nil; pendingRefresh?.cancel(); pendingRefresh = nil }   // from AppContainer.shutdown()
```

## 2. **Debounce and wake tasks replace their predecessor; one task per purpose**

`DisplayReconfigurationObserver` yields several events per cable plug (one per display, add + reconfigure, plus the mirror partner). A new `Task` per event means N sleeping tasks each holding `self`, N re-enumerations through `CGGetOnlineDisplayList` and `NSScreen.screens`, and N `reapplyIfNeeded` runs racing each other for a display transaction. The same applies to `AppContainer.wakeTask`: a second `didWakeNotification` within two seconds must cancel the first.

Grep: `pendingRefresh = Task|wakeTask = Task` not preceded by `?.cancel()`; `Task \{[^}]*Task\.sleep` not stored.

Wrong:
```swift
private func handle(_ change: DisplayChange) {
    Task { try? await Task.sleep(for: .seconds(1)); self.refresh() }   // one per event; all run; all retain self while sleeping
}
```
Right:
```swift
pendingRefresh?.cancel()
pendingRefresh = Task { [weak self] in
    try? await Task.sleep(for: Self.refreshDebounce)
    guard let self, !Task.isCancelled else { return }
    refresh()
    if case let .added(displayID) = change { await reapplyIfNeeded(displayID: displayID) }
}
```

## 3. **The reconfiguration callback is registered once with `passUnretained`, removed in `deinit` with the same pointer, and has exactly one owner**

`CGDisplayRegisterReconfigurationCallback` stores a raw pointer. `passRetained` leaks the observer (+1 nobody balances, so `deinit` never runs and the callback is never removed); a missing `CGDisplayRemoveReconfigurationCallback` lets the window server call into freed memory on the next display change, long after the owner is gone. The observer is a `let` on `DisplayEnumerator`, is `Sendable` with only `let` properties, and the C callback is a top-level function that captures nothing.

Grep: `CGDisplayRegisterReconfigurationCallback` (expect one hit, with `passUnretained`); `CGDisplayRemoveReconfigurationCallback` in the same file's `deinit`; `passRetained`.

Wrong:
```swift
init() {
    CGDisplayRegisterReconfigurationCallback(callback, Unmanaged.passRetained(self).toOpaque())   // never released
}
// or: no deinit at all → dangling pointer on the next plug
```
Right:
```swift
init() { CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque()) }
deinit {
    CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
    continuation.finish()
}
```

## 4. **Every `CGBeginDisplayConfiguration` is balanced by exactly one `CGCompleteDisplayConfiguration` or `CGCancelDisplayConfiguration`**

A begun configuration is a window-server object; leaking it leaves a pending transaction that blocks the next one and keeps the display in whatever intermediate state it reached. `Complete` releases the ref whether or not it succeeds, so a `Cancel` after a failed `Complete` is a double release. Do every precondition (`CGDisplayIsOnline`, catalog lookup) *before* `Begin`, so that after `Begin` the only exits are `Cancel` + throw or `Complete`.

Grep: count `CGBeginDisplayConfiguration` vs `CGCompleteDisplayConfiguration|CGCancelDisplayConfiguration` per function; `throw|return` between `Begin` and `Complete` without `Cancel` on the line before.

Wrong:
```swift
let begin = CGBeginDisplayConfiguration(&config)
guard begin == .success, let config else { throw .configurationFailed(stage: "begin", code: begin.rawValue) }
guard CGDisplayIsOnline(displayID) != 0 else { throw .displayNotFound }        // config leaked, transaction pending
```
Right (`DisplayModeService.apply`):
```swift
guard CGDisplayIsOnline(displayID) != 0 else { throw .displayNotFound }        // before Begin
guard let cgMode = DisplayModeCatalog.cgMode(matching: mode, on: displayID) else { throw .modeUnavailable }
var config: CGDisplayConfigRef?
let begin = CGBeginDisplayConfiguration(&config)
guard begin == .success, let config else { throw .configurationFailed(stage: "begin", code: begin.rawValue) }
let configure = CGConfigureDisplayWithDisplayMode(config, displayID, cgMode, nil)
guard configure == .success else { CGCancelDisplayConfiguration(config); throw .configurationFailed(stage: "configure", code: configure.rawValue) }
let complete = CGCompleteDisplayConfiguration(config, .permanently)             // releases config either way
guard complete == .success else { throw .configurationFailed(stage: "complete", code: complete.rawValue) }
```

## 5. **A `CGVirtualDisplay` has one strong reference in the process: `VirtualDisplayService.handles`**

The virtual display exists exactly as long as its object is retained. A second reference (a snapshot field, a closure capture, a `Task` holding the handle across `deactivate`, a debug cache) keeps the display online after "Tela virtual" is turned off: the panel stays in a mirror set whose master the user cannot see, and only quitting the app fixes it. The failure path of `activate` must drop the handle before rethrowing. `Handle.virtualID` is a plain `UInt32`, which is what `waitUntilRemoved` and the enumerator use; nothing else needs the object. The descriptor's `terminationHandler` stays `nil` (the block would retain its captures and is known to crash at process exit).

Grep: `CGVirtualDisplay\b` outside `VirtualDisplayService.swift` and `CGVirtualDisplay.h` (expect none); `handles\[` assignments; `terminationHandler`.

Wrong:
```swift
struct DisplaySnapshot { let virtualDisplay: CGVirtualDisplay? }       // one owner per snapshot copy: never released
let handle = handles[display.id]
Task { [handle] in await waitUntilRemoved(handle!.virtualID) }          // the captured object outlives deactivate()
```
Right:
```swift
private var handles: [UInt32: Handle] = [:]                             // the only strong reference
func deactivate(for displayID: UInt32) async throws(LiteDisplayError) {
    guard let handle = handles[displayID] else { return }
    if CGDisplayMirrorsDisplay(displayID) == handle.virtualID { try unmirror(physical: displayID) }
    handles[displayID] = nil                                             // last reference: the window server removes the display
    try await waitUntilRemoved(handle.virtualID)                         // UInt32, not the object
}
```

## 6. **Selector-based observers remove `self` in `stop()` and `deinit`; handler closures capture weakly**

`SleepWakeObserver` uses `addObserver(_:selector:name:object:)` on purpose: `deinit` of a `@MainActor` class cannot touch isolated state in Swift 6, but `removeObserver(self)` is safe there. A block-based `addObserver(forName:)` returns a token that is *not* removed automatically and whose block retains everything it mentions. The closures `AppContainer` passes in capture `[weak self]`, otherwise container → observer → closure → container.

Grep: `addObserver\(forName:` (expect none); `addObserver\(self` paired with `removeObserver\(self` in `stop\(\)` and `deinit`; `onSleep: \{` without `[weak self]`.

Wrong:
```swift
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
    self.suspendVirtualDisplays()                                        // token dropped; block retains self; never removed
}
```
Right:
```swift
sleepWake = SleepWakeObserver(
    onSleep: { [weak self] in self?.suspendVirtualDisplays() },
    onWake: { [weak self] in self?.resumeVirtualDisplays() }
)
// SleepWakeObserver: init adds two selector observers; stop() and deinit both call removeObserver(self)
```

## 7. **`@Observable` objects are created once in `AppContainer` (or `@State`), never inside `body`; callback properties capture weakly**

`AppContainer.init` builds every store, service and view model once; views reach them through `@Environment(AppContainer.self)`. A `MonitorsViewModel()` in a `body` would create a new observation task (rule 1) per render and abandon the old one. `ProfilesViewModel.displaysDidChange` is a stored closure that the container sets; a strong capture there is a two-object cycle (container → profiles → closure → container).

Grep: `ViewModel\(` outside `AppContainer.swift`, `@State` and tests; `displaysDidChange = \{` without `[weak self]`; `var \w+: \(.*\) -> Void` properties.

Wrong:
```swift
var body: some View { MonitorDetailView(viewModel: MonitorsViewModel(provider: …)) }   // new object and task per render
profiles.displaysDidChange = { self.monitors.refresh() }                                // cycle
```
Right:
```swift
@Environment(AppContainer.self) private var container                   // views borrow, never own
profiles.displaysDidChange = { [weak self] in self?.monitors.refresh() }
```

## 8. **The privileged `Process` is a local in a static function: pipes drained before `waitUntilExit`, no stored reference, no `terminationHandler`**

`osascript` can write a long stderr (AppleScript errors); if the parent calls `waitUntilExit()` before reading the pipe, the child blocks on a full pipe and the app hangs with the authentication dialog gone. A `terminationHandler` closure retains its captures until the process ends, and a `Process` stored on `self` keeps the pipe file handles open for the life of the runner. Stdout and stdin go to `FileHandle.nullDevice` so nothing is buffered for a reader that does not exist.

Grep: `Process\(\)` (expect one, in `PrivilegedRunner.execute`); `waitUntilExit` preceded by `readDataToEndOfFile`; `terminationHandler` on a `Process`; `var process`.

Wrong:
```swift
process.terminationHandler = { _ in self.finish() }                     // retains self; fires on an arbitrary thread
try process.run()
process.waitUntilExit()                                                 // deadlocks when stderr fills the pipe
let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
```
Right:
```swift
private static func execute(_ script: String) -> Outcome {
    let process = Process(); let errorPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: osascript); process.arguments = ["-e", script]
    process.standardError = errorPipe; process.standardOutput = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
    do { try process.run() } catch { return Outcome(status: -1, stderr: error.localizedDescription) }
    let data = errorPipe.fileHandleForReading.readDataToEndOfFile()     // drain first
    process.waitUntilExit()
    return Outcome(status: process.terminationStatus, stderr: String(decoding: data, as: UTF8.self))
}
```

## 9. **The override staging directory is removed in `defer`, on every path**

`HiDPIOverrideInstaller.install` writes the plist into a private `0700` directory under `FileManager.default.temporaryDirectory`; the user may cancel the prompt (`privilegeDenied`), the copy may fail, or verification may throw. Without `defer` each attempt leaves a directory with the generated plist behind. The `defer` must be placed after the directory URL is known and before the first `try`.

Grep: `temporaryDirectory` in a function without `defer { try? FileManager.default.removeItem`.

Wrong:
```swift
try stage(data, at: stagedFile, in: stagingDirectory)
try await runner.run(command, prompt: prompt)                            // throws on cancel: directory stays
try? FileManager.default.removeItem(at: stagingDirectory)
```
Right:
```swift
let stagedFile = stagingDirectory.appendingPathComponent(profile.fileName)
defer { try? FileManager.default.removeItem(at: stagingDirectory) }     // success, throw and cancellation
try stage(data, at: stagedFile, in: stagingDirectory)
try await runner.run(command, prompt: prompt)
try verify(profile)
```

## 10. **CoreFoundation "Create"/"Copy" results are taken with `takeRetainedValue()`; bridged `CGDisplayMode` arrays are not retained by hand**

`CGDisplayCreateUUIDFromDisplayID` returns `Unmanaged<CFUUID>?` under the Create rule: `takeUnretainedValue()` leaks one `CFUUID` per display per enumeration, and the enumerator runs on every refresh and every reconfiguration event. `CGDisplayCopyDisplayMode` and `CGDisplayCopyAllDisplayModes` are annotated for ARC in Swift and need nothing. Never `takeRetainedValue()` on a "Get" result (over-release, crash).

Grep: `Unmanaged|takeUnretainedValue|takeRetainedValue|CFRelease|CFRetain`.

Wrong:
```swift
let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)!.takeUnretainedValue()   // +1 leaked per call; force unwrap on a nullable
```
Right:
```swift
if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
    return CFUUIDCreateString(nil, uuid) as String
}
return "\(vendor)-\(product)-\(serial)"
```

## 11. **Teardown at exit is synchronous and finishes before the process exits**

Dropping the `VirtualDisplayService` with mirrors active leaves the panel mirroring a display that vanished with the process; the window server recovers eventually, but the user sees a black monitor. `AppDelegate.applicationShouldTerminate` calls the synchronous `container.shutdown()` (stops the view model, the sleep observer and `wakeTask`, then `virtualDisplays.releaseAll()`, which unmirrors in a transaction and drops the handles without polling) and returns `.terminateNow`. It must not return `.terminateLater` and reply from a main-actor `Task`: when `NSApp.terminate` is itself called from a main-actor job (the debug automation, or any future `Task`), the reply job can never run and the process hangs inside `terminate:` (observed on 2026-10-22). `NSSupportsSuddenTermination` is `false` in `Info.plist` so the delegate always runs. Any new resource that needs cleanup at exit is released synchronously from `shutdown()`, not from a `deinit` and not behind an `await`.

Grep: `applicationShouldTerminate` (expect `container.shutdown()` then `.terminateNow`; `.terminateLater` and `reply(toApplicationShouldTerminate:` must not appear); `releaseAll\(\)` (expect `shutdown()` only); `deactivateAll\(\)` (expect `suspendVirtualDisplays()` only); `NSSupportsSuddenTermination`.

Wrong:
```swift
func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Task { @MainActor in await container.shutdown(); NSApp.reply(toApplicationShouldTerminate: true) }
    return .terminateLater   // deadlocks when terminate(nil) came from a main-actor Task; exits early if the Task is dropped
}
```
Right:
```swift
func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    container.shutdown()     // synchronous: stop tasks/observers, unmirror, drop the virtual display handles
    return .terminateNow
}
```

## How to verify dynamically

Static review cannot see what the window server retains; run this after the code pass, with the user watching the external monitor.

1. Build Debug (products under `$TMPDIR`), record the display state, launch the app outside Xcode:
   ```sh
   swift scripts/dump-modes.swift > "${TMPDIR}modes-before.txt"
   open "${TMPDIR}LiteDisplay-DerivedData/Build/Products/Debug/LiteDisplay.app"
   ```
2. In the menu bar popover toggle "Texto nítido" 10× (ending in the state it started in). In the main window enable and disable "Tela virtual" 10×. Open and close the main window 10× (the menu-bar extra keeps the app alive).
3. Leaked objects on the running process (launch with `MallocStackLogging=1 open -W …` first when you want allocation stacks):
   ```sh
   pid=$(pgrep -x LiteDisplay)
   leaks "$pid" | tail -n 5                                   # expected: "0 leaks for 0 total leaked bytes"
   leaks "$pid" | grep -E 'ROOT LEAK|LiteDisplay\.'           # leaked LiteDisplay types, if any
   ```
4. Instruments Leaks template attached to the running app:
   ```sh
   xcrun xctrace record --template Leaks --attach "$pid" --time-limit 30s --output /tmp/leaks.trace
   open /tmp/leaks.trace                                      # expected: no leak markers; Allocations "Persistent" flat
   ```
5. Prove the display came back: `swift scripts/dump-modes.swift > "${TMPDIR}modes-after.txt"; diff "${TMPDIR}modes-before.txt" "${TMPDIR}modes-after.txt"` shows the same `CURRENT` line and no extra display (vendor `0x4c44` would be a lingering virtual display). `system_profiler SPDisplaysDataType | grep -A3 XB273` shows `Mirror: Off` after the last "Tela virtual" off.
6. Xcode Memory Graph (*Scheme > Diagnostics > Malloc Stack Logging*), filter by "LiteDisplay" and "CGVirtual": expected with the virtual display off: 0 `CGVirtualDisplay`, 0 `CGVirtualDisplayDescriptor`, 1 `DisplayReconfigurationObserver`, 1 `SleepWakeObserver`, one instance of each view model and store, no leak badges. `footprint "$pid"` before and after the cycles differs by less than roughly 20 MB.

## Severity guide

| Severity | Classify here when… | Typical findings from this file |
|---|---|---|
| High | A window-server resource outlives its owner or is used after free, or the user's display stays mirrored/configured with no way back short of a relaunch | Second owner of a `CGVirtualDisplay` or a handle captured past `deactivate` (#5); `passRetained` or missing `CGDisplayRemoveReconfigurationCallback` (#3); begun configuration without `Cancel`/`Complete` on a path (#4); `.terminateNow` before `deactivateAll()` (#11); pipe read after `waitUntilExit` (#8) |
| Medium | A bounded leak per user action or a duplicate worker doing real work (extra transactions, extra enumerations) | Observation/debounce/wake task not cancelled or duplicated (#1, #2); block observer token dropped or strong `onSleep` capture (#6); `@Observable` created in `body` or strong `displaysDidChange` (#7); staging directory left behind on cancel (#9); `takeUnretainedValue` on a Create result (#10) |
| Low | Lifetime is extended but bounded and released on teardown; style-level `weak` choices | Strong `self` in a short one-shot `Task` that `perform` serialises (#1); `Process` stdout left as a pipe that is drained anyway (#8); a `Handle` struct with an unused field (#5) |
