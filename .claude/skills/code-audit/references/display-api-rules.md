# Display API rules — LiteDisplay code audit

**Scope.** Everything that talks to the window server or shapes what it is told: `Infrastructure/CoreGraphics/*` (enumeration, mode tables, the mode transaction, the reconfiguration callback), `Infrastructure/VirtualDisplay/*` (the private 2x display and the mirror transaction), `Shared/Extensions/CGDisplayMode+DisplayMode.swift` (the only bridge to `DisplayMode`), `Domain/Models/{DisplayMode,DisplaySnapshot,ModeSelection,HiDPIOverrideProfile}.swift` (identity, usability, selection, override bytes), `Domain/UseCases/SetSharpnessUseCase.swift` (order of operations), `App/AppContainer.swift` (sleep/wake and relaunch) and `Features/Monitors/MonitorsViewModel.swift` (ignoring the app's own callbacks). The thing at risk is the user's monitor: a transaction without `Cancel` leaves a pending configuration; a `.forSession` physical mode or `CGDisplaySetDisplayMode` reverts at quit; a lost virtual display handle leaves the panel mirroring something invisible; a mode changed on the virtual display makes it linger; a wrong `hasUsableHiDPI` hides the override card or offers a 45 ppi desktop. The acceptance target is that after any sequence of actions, `swift scripts/dump-modes.swift` shows the panel on the mode the user chose and no display with vendor `0x4c44` unless "Tela virtual" is on.

## 1. **Mode changes are a Begin → Configure → Complete transaction with `Cancel` on every failure in between, verified afterwards**

`CGBeginDisplayConfiguration` opens a transaction the window server holds until `Complete` or `Cancel`. Every exit between those two must call `CGCancelDisplayConfiguration`; `Complete` releases the ref on success *and* failure, so nothing is called after it. Preconditions (`CGDisplayIsOnline`, catalog lookup) run before `Begin`. After `Complete`, the result is checked against the window server (`CGDisplayCopyDisplayMode(id).ioDisplayModeID == target`, or `CGDisplayMirrorsDisplay(physical) == virtualID`) and a mismatch is `verificationFailed`: the window server can accept a configuration and still pick a different timing.

Grep: `CGBeginDisplayConfiguration` (expect `DisplayModeService.apply`, `VirtualDisplayService.mirror/unmirror/restoreRateIfNeeded`); each `throw|return` between `Begin` and `Complete` preceded by `CGCancelDisplayConfiguration`; `CGCancelDisplayConfiguration` after `CGCompleteDisplayConfiguration` (double release).

Wrong:
```swift
let begin = CGBeginDisplayConfiguration(&config)
guard begin == .success, let config else { throw .configurationFailed(stage: "begin", code: begin.rawValue) }
guard CGConfigureDisplayWithDisplayMode(config, displayID, cgMode, nil) == .success else { throw .modeUnavailable }   // transaction left pending
let complete = CGCompleteDisplayConfiguration(config, .permanently)
guard complete == .success else { CGCancelDisplayConfiguration(config); throw … }                                 // config already released
```
Right:
```swift
let configure = CGConfigureDisplayWithDisplayMode(config, displayID, cgMode, nil)
guard configure == .success else { CGCancelDisplayConfiguration(config); throw .configurationFailed(stage: "configure", code: configure.rawValue) }
let complete = CGCompleteDisplayConfiguration(config, .permanently)
guard complete == .success else { throw .configurationFailed(stage: "complete", code: complete.rawValue) }
guard let now = CGDisplayCopyDisplayMode(displayID), now.ioDisplayModeID == cgMode.ioDisplayModeID else { throw .verificationFailed }
```

## 2. **Physical modes commit `.permanently`; mirrors onto a virtual display commit `.forSession`; `CGDisplaySetDisplayMode` is never called**

`.permanently` writes the choice into the window server's display preferences, so the panel comes back on that mode after a reconnect, a reboot and after LiteDisplay quits; that is the product. `CGDisplaySetDisplayMode` is documented in `CGDirectDisplay.h` as the Begin/Configure/Complete sequence with `kCGConfigureForAppOnly`: the mode reverts when the process exits, and the user sees the monitor flip back to blurry on quit. A mirror whose master is a virtual display must be `.forSession`, because the master disappears with the process and a permanent mirror record would be stale on the next login. `restoreRateIfNeeded` (physical panel back to its native rate after joining the mirror set) is a physical change and is `.permanently`.

Grep: `CGDisplaySetDisplayMode` anywhere (hard FAIL in the script); `CGCompleteDisplayConfiguration\(config, \.(forSession|forAppOnly)\)` in `DisplayModeService` (expect none); `\.permanently` in `mirror\(|unmirror\(` (expect none).

Wrong:
```swift
CGDisplaySetDisplayMode(displayID, cgMode, nil)                           // kCGConfigureForAppOnly: reverts at quit
CGCompleteDisplayConfiguration(config, .forSession)                         // physical mode lost at logout
```
Right:
```swift
CGCompleteDisplayConfiguration(config, .permanently)                        // DisplayModeService.apply, restoreRateIfNeeded
CGCompleteDisplayConfiguration(config, .forSession)                         // VirtualDisplayService.mirror / unmirror
```

## 3. **Mode tables are read with `kCGDisplayShowDuplicateLowResolutionModes`, filtered by `isUsableForDesktopGUI()`, stripped of stretched/interlaced flags, and deduplicated deterministically**

Without the option, `CGDisplayCopyAllDisplayModes` hides the HiDPI "looks like" modes that are the whole point. `isUsableForDesktopGUI()` removes modes the window server would refuse for the desktop. Stretched (`0x0800`) and interlaced (`0x0040`) timings are dropped so a 1280×1024-stretched entry never wins a size match. Duplicates by `ModeKey` are resolved by higher `ioFlags` then lower id, so the same table always yields the same choice and `ModeSelection` tests stay deterministic.

Grep: `CGDisplayCopyAllDisplayModes` — the same file must contain `kCGDisplayShowDuplicateLowResolutionModes`; `isUsableForDesktopGUI`; `stretchedFlag|interlacedFlag`.

Wrong:
```swift
let modes = (CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode]) ?? []   // no HiDPI modes on most external panels
```
Right:
```swift
let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
return (CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]) ?? []
    .filter { $0.isUsableForDesktopGUI() && $0.ioFlags & (stretchedFlag | interlacedFlag) == 0 }
```

## 4. **Mode identity is `ioDisplayModeID` first and `ModeKey` second; `CGDisplayMode` objects are never compared across copies and mode ids are never persisted**

`ioDisplayModeID` is unique per connection: the table is rebuilt on every reconnect and after an override install, and ids shift. `DisplayModeCatalog.cgMode(matching:on:)` tries the id and falls back to the geometry key (`width`, `height`, `pixelWidth`, `pixelHeight`, centi-hertz). Two `CGDisplayMode` objects from different `CopyAllDisplayModes` calls are different objects even for the same timing, so `==`/`isEqual`/`===` are wrong. Profiles and `AppSettings` store `DisplaySettings` (method, `DisplaySize`, refresh rate) and resolve against the live table through `ModeSelection` when applied.

Grep: `== cgMode\b|isEqual\(|=== ` on `CGDisplayMode` values; `ioDisplayModeID|\.id\b` stored in `Codable` types; `cgMode\(matching:` used by every transaction.

Wrong:
```swift
if DisplayModeCatalog.cgModes(for: id).contains(where: { $0 == savedCGMode }) { … }   // never true after a reconnect
struct DisplaySettings: Codable { var modeID: Int32 }
```
Right:
```swift
static func cgMode(matching mode: DisplayMode, on displayID: CGDirectDisplayID) -> CGDisplayMode? {
    let all = cgModes(for: displayID)
    return all.first { $0.ioDisplayModeID == mode.id } ?? all.first { $0.domainMode.key == mode.key }
}
```

## 5. **Framework display objects stay inside `@MainActor` Infrastructure; Domain sees `DisplayMode`, `DisplaySnapshot` and `UInt32` ids only**

`CGDisplayMode`, `CGDisplayConfigRef` and `CGVirtualDisplay*` are not `Sendable`. `CGDisplayMode+DisplayMode.swift` (`domainMode`) converts once at the catalog; use cases receive `DisplaySnapshot` values with `[DisplayMode]`, decide with `ModeSelection`, and pass `DisplayMode` back to `DisplayModeApplying.apply`, which looks the live object up again. `VirtualDisplayControlling` exposes `Set<UInt32>` of owned ids, never handles.

Grep: `CGDisplayMode|CGVirtualDisplay|CGDisplayConfigRef` in `Domain/|Features/|App/`; `import CoreGraphics` in `Domain/` (lint error).

Wrong:
```swift
protocol DisplayModeApplying { func apply(_ mode: CGDisplayMode, to displayID: UInt32) throws }   // framework type in Domain
```
Right:
```swift
@MainActor protocol DisplayModeApplying: AnyObject { func apply(_ mode: DisplayMode, to displayID: UInt32) throws(LiteDisplayError) }
extension CGDisplayMode { var domainMode: DisplayMode { DisplayMode(id: ioDisplayModeID, width: width, …, ioFlags: ioFlags) } }
```

## 6. **Reconfiguration callbacks fire for the app's own transactions; they are ignored while `isApplying`, debounced, and followed by a fresh enumeration**

Every transaction LiteDisplay commits produces begin + complete callbacks for the panel and, for mirrors, for the virtual display too; a cable plug produces several more. `DisplayReconfigurationObserver.handle` drops `.beginConfigurationFlag`; `MonitorsViewModel.handle` drops everything while `isApplying` (the `refresh()` at the end of `perform` covers those), debounces 1.5 s so `NSScreen.screens` has caught up with the window server, then re-enumerates. Only `.added` triggers `ReapplyOnConnectUseCase`. Acting on the event's display id without re-enumerating uses a display that may already be gone.

Grep: `beginConfigurationFlag` guard in the observer; `guard !isApplying` at the top of `handle(_:)`; `refreshDebounce`; `externalDisplays()` called inside the debounced task before any action.

Wrong:
```swift
private func handle(_ change: DisplayChange) {
    refresh()                                                    // runs mid-transaction, reads a half-applied state, re-enters reapply
    if case let .added(id) = change { Task { await reapplyIfNeeded(displayID: id) } }
}
```
Right:
```swift
private func handle(_ change: DisplayChange) {
    guard !isApplying else { return }                            // our own transaction; perform() refreshes afterwards
    pendingRefresh?.cancel()
    pendingRefresh = Task { [weak self] in
        try? await Task.sleep(for: Self.refreshDebounce)
        guard let self, !Task.isCancelled else { return }
        refresh()
        if case let .added(displayID) = change { await reapplyIfNeeded(displayID: displayID) }
    }
}
```

## 7. **`VirtualDisplayService.handles` is the only owner of a `CGVirtualDisplay`; deactivation unmirrors, restores the panel's main role, releases, then waits briefly; a lingering display is reported as `.lingering` and the app relaunches itself**

The display exists while the object is retained. `activate` refuses a second instance for the same panel, stores the handle before waiting so a failure path can release it, and on any error sets `handles[id] = nil` before rethrowing. `deactivate` first unmirrors (if the panel still mirrors the virtual id), then drops the handle, then polls `CGDisplayIsOnline` up to 2 s. If the display is still online, the error reaches `MonitorDetailView`, which shows "Reabrir o LiteDisplay" bound to `AppContainer.relaunch()` (new instance, then terminate: the only reliable way to make the window server drop it). The descriptor's `terminationHandler` stays `nil` (a block there crashes at process exit). `ownedDisplayIDs` and the stamped vendor id `0x4C44` let `DisplayEnumerator` hide virtual displays, including one left by a previous process.

Grep: `CGVirtualDisplay\(` (expect one, in `makeVirtualDisplay`); `handles\[display.id\] = nil` in the `catch` of `activate`; `terminationHandler = nil`; `virtualDisplayLingering` paired with `relaunch\(\)`; `virtualDisplayVendorID` used in the enumerator filter.

Wrong:
```swift
func deactivate(for displayID: UInt32) async throws(LiteDisplayError) {
    handles[displayID] = nil                                     // released while still the mirror master: panel goes dark until the window server recovers
}
descriptor.terminationHandler = { _, _ in Log.virtualDisplay.info("gone") }   // crashes at exit
```
Right:
```swift
guard let handle = handles[displayID] else { return }
if CGDisplayMirrorsDisplay(displayID) == handle.virtualID { try unmirror(physical: displayID) }
handles[displayID] = nil
try await waitUntilRemoved(handle.virtualID)                     // throws .virtualDisplayLingering after removalTimeout
```

## 8. **The virtual display's mode is changed only when it differs from the target; polling uses `Task.sleep` with deadlines (online 3 s, removal 2 s, 50 ms interval)**

`CGVirtualDisplayMode` sizes are **points**: with `hiDPI = 1` the window server adds the 2x variant of every listed size whose doubled pixels fit `maxPixelsWide/High`, and that 2x mode becomes the display's native/default mode. List the panel's native point size (1920×1080) with `maxPixels` = 2× (3840×2160); listing 3840×2160 instead yields a 1x-only display with no usable 2x mode (observed on macOS 27). A display created with the same vendor/product/serial as one just released may come up with an empty mode table, so identities stay stable and are not recycled within a session.

Changing the virtual display's mode after creation is what makes it linger after release (documented by go-macos/virtualdisplay and reproduced here). `makeVirtualDisplay` offers the panel's rate and a 60 Hz fallback in `applySettings`, so the window server usually comes up on the right mode and `mirror` skips `CGConfigureDisplayWithDisplayMode` when `currentMode(of: virtualID)?.id == target.id`. Polling without yielding would block the main actor the window server may need to finish the configuration.

Grep: `currentMode\(of: virtualID\)\?\.id != target\.id` guard before the virtual mode configure; `onlineTimeout|removalTimeout|pollInterval`; `usleep|Thread\.sleep` (expect none).

Wrong:
```swift
let set = CGConfigureDisplayWithDisplayMode(config, virtualID, cgTarget, nil)    // unconditional: display lingers after release
while CGDisplayIsOnline(virtualID) == 0 {}                                        // spins on main forever if it never comes up
```
Right:
```swift
if DisplayModeCatalog.currentMode(of: virtualID)?.id != target.id {
    let set = CGConfigureDisplayWithDisplayMode(config, virtualID, cgTarget, nil)
    guard set == .success else { CGCancelDisplayConfiguration(config); throw .configurationFailed(stage: "virtual mode", code: set.rawValue) }
}
let deadline = ContinuousClock.now + Self.onlineTimeout
while CGDisplayIsOnline(virtualID) == 0 { guard ContinuousClock.now < deadline else { throw .virtualDisplayFailed("timeout") }; try? await Task.sleep(for: Self.pollInterval) }
```

## 9. **Before mirroring, the panel is put on its native 1x mode at the preferred rate; after mirroring, a dropped refresh rate is restored**

`SetSharpnessUseCase.ensureNativeMode` runs before `activate` so the panel mirrors at its full pixel size (a 1904×1071 HiDPI mode would be mirrored at that size). Joining a mirror set can make the window server pick a "safe" lower rate for the panel; `restoreRateIfNeeded` compares `currentMode(of: physical)` with the wanted rate and re-applies the native mode `.permanently`. Verification after the mirror transaction is `CGDisplayMirrorsDisplay(physical) == virtualID`.

Grep: `ensureNativeMode` called in the `.virtualDisplay` branch before `activate`; `restoreRateIfNeeded` after the mirror `Complete`; `CGDisplayMirrorsDisplay\(physical\) == virtualID`.

Wrong:
```swift
case .virtualDisplay:
    try await virtualDisplays.activate(for: display)             // panel still on a HiDPI mode: mirror is scaled twice, text soft again
```
Right:
```swift
case .virtualDisplay:
    guard virtualDisplays.isAvailable else { throw .virtualDisplayUnavailable }
    if !virtualDisplays.isActive(for: display.id) {
        try ensureNativeMode(on: display, preferredRate: preferredRate)
        try await virtualDisplays.activate(for: display)
    }
```

## 10. **Sleep unmirrors (`suspendAll`) and wake re-mirrors the same virtual display (`resumeAll`); quit releases everything synchronously**

A virtual mirror master is known to wedge system sleep. `AppContainer.suspendVirtualDisplays` (on `NSWorkspace.willSleepNotification`) remembers the affected `persistentID`s and calls `deactivateAll()`; `resumeVirtualDisplays` (on `didWakeNotification`) waits 2 s, re-enumerates and re-applies `.virtualDisplay` through the use case, cancelling any previous `wakeTask`. On quit, `applicationShouldTerminate` calls the synchronous `shutdown()`, which ends with `VirtualDisplayService.releaseAll()` (unmirror transaction, then drop the handles without waiting), and returns `.terminateNow`. Letting the process exit, sleep or crash with mirrors active leaves the panel mirroring a display that no longer exists; awaiting the teardown behind `.terminateLater` deadlocks when `terminate` was called from a main-actor `Task` (see memory rule 11).

Grep: `willSleepNotification|didWakeNotification` (expect `SleepWakeObserver` only); `deactivateAll\(\)` call sites (`suspendVirtualDisplays` only); `releaseAll\(\)` (`shutdown` only); `\.terminateLater` in `AppDelegate` (expect none).

Wrong:
```swift
func applicationWillTerminate(_ notification: Notification) { Task { await container.shutdown() } }   // process is gone before the unmirror completes
```
Right:
```swift
func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    container.shutdown()   // synchronous unmirror + release
    return .terminateNow
}
```

## 11. **`hasUsableHiDPI` judges a HiDPI mode by physical density (≥ 60 points per inch from the EDID size), not by the `isHiDPI` flag alone**

macOS offers a stock "looks like 960×540 @2x" mode on every 1080p panel. It *is* HiDPI, but on a 24-inch panel it is about 45 ppi: a desktop with four windows' worth of space gone. Counting it hides the override card (`!display.hasUsableHiDPI`) and makes "Texto nítido" pick `.hiDPI` with a giant UI. `PhysicalSize.pointsPerInch(for:)` divides the mode's point width by the panel width in inches; the threshold is `DisplaySnapshot.minimumUsablePointsPerInch = 60`. When the EDID reports no size, the fallback is `mode.width * 2 > native.width`, which also rejects the exact half-resolution mode.

Grep: `hasUsableHiDPI` implementation references `pointsPerInch|minimumUsablePointsPerInch`; `modes.contains(where: \\.isHiDPI)` or `isHiDPI` used alone as "HiDPI available".

Wrong:
```swift
var hasUsableHiDPI: Bool { modes.contains(where: \.isHiDPI) }      // true for every 1080p panel because of 960×540@2x
```
Right:
```swift
var hasUsableHiDPI: Bool {
    modes.contains { mode in
        guard mode.isHiDPI else { return false }
        if let ppi = physicalSize.pointsPerInch(for: mode) { return ppi >= Self.minimumUsablePointsPerInch }
        guard let native = nativeSize else { return false }
        return mode.width * 2 > native.width
    }
}
```

## 12. **`/Library/Displays` is written only by `HiDPIOverrideInstaller` through the root command, after a click; the byte layout lives in `HiDPIOverrideProfile`; new modes are expected only after a reconnect**

The override path is `overridesRoot/DisplayVendorID-<hex>/DisplayProductID-<hex>` with hex from `CGDisplayVendorNumber`/`CGDisplayModelNumber` validated by `hasValidIdentifiers`. Entries are 8-byte 1x sizes and 16-byte 2x sizes with flags `0x00000009`, `0x00200000`, generated for the native width down to 1280 in steps of 16 at the panel's aspect ratio. The window server reads overrides at connection time, so after an install the view model records the `persistentID` in `pendingOverrides`, shows the reconnect notice, and never tries `.hiDPI` until `hasUsableHiDPI` turns true. No code writes `~/Library/Displays`, and nothing calls the installer on reconnect or at launch.

Grep: `Library/Displays` outside `HiDPIOverrideProfile.swift` and user-facing strings; `installer\.install|overrideInstaller\.execute` outside `MonitorsViewModel.installOverride`; `pendingOverrides` cleared only when `hasUsableHiDPI` is true.

Wrong:
```swift
try data.write(to: URL(fileURLWithPath: "/Library/Displays/Contents/Resources/Overrides/\(dir)/\(file)"))   // EPERM, or worse if run as root elsewhere
await setMethod(.hiDPI, for: display)                                                    // right after install: modeUnavailable, confusing
```
Right:
```swift
_ = try await overrideInstaller.execute(for: display)
pendingOverrides.insert(display.persistentID)
notice = String(localized: "Perfil HiDPI instalado. Desconecte e reconecte o monitor (ou reinicie o Mac) para as novas resoluções aparecerem.")
```

## 13. **Enumeration is defensive: EDID UUID via `takeRetainedValue()`, builtin/virtual/vendor-0x4C44 filtered, unknown physical size handled, failures return an empty list**

`CGDisplayCreateUUIDFromDisplayID` follows the Create rule and is nullable (some docks and DisplayLink adapters return nil): `?.takeRetainedValue()` with a vendor-product-serial fallback for `persistentID`. `CGDisplayScreenSize` returns zero for panels without EDID size, which `PhysicalSize.isKnown` turns into the descriptor's `fallbackSizeMM` and the density fallback in rule 11. `CGGetOnlineDisplayList` failure logs and returns `[]` so the UI shows "Nenhum monitor externo conectado" instead of crashing. Names come from `NSScreen.screen(for:)` (`NSScreenNumber`), which can lag one run loop behind the window server, hence the debounce in rule 6.

Grep: `CGDisplayCreateUUIDFromDisplayID` on a line with `takeRetainedValue`; `CGDisplayIsBuiltin|ownedDisplayIDs|virtualDisplayVendorID` in the enumerator filter; `maxDisplays`; `!` after `CGDisplayCreateUUIDFromDisplayID|NSScreen.screen`.

Wrong:
```swift
let uuid = CGDisplayCreateUUIDFromDisplayID(displayID).takeUnretainedValue()   // leak on every refresh; crash when nil
let name = NSScreen.screen(for: displayID)!.localizedName                       // nil during the first callbacks after a plug
```
Right:
```swift
if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() { return CFUUIDCreateString(nil, uuid) as String }
let name = NSScreen.screen(for: displayID)?.localizedName ?? String(localized: "Monitor \(String(vendor, radix: 16)):\(String(product, radix: 16))")
```

## 14. **Only four configure calls exist in the app, and nothing captures, fades or rearranges the user's layout**

`CGConfigureDisplayWithDisplayMode`, `CGConfigureDisplayMirrorOfDisplay` (with source `0` to unmirror) and, only inside `VirtualDisplayService`, `CGConfigureDisplayOrigin` are all the product needs. The origin call is used for exactly two things: giving the mirror *source* (the virtual display) the origin when the panel was the main display, so the menu bar stays on the panel, and giving the panel the origin back when it is unmirrored; setting the origin of a display that is itself mirroring removes it from the set (CGDisplayConfiguration.h). Anywhere else `CGConfigureDisplayOrigin` rearranges the user's layout, `CGDisplayCapture`/`CGDisplayRelease` take the display away from the desktop, `CGDisplayFade*` reservations can leave a black screen on a thrown error, and `CGRestorePermanentDisplayConfiguration` resets every display at once. `scripts/dump-modes.swift` is read-only diagnostics and the only display tool the audit runs by itself.

Grep: `CGDisplayCapture|CGDisplayRelease|CGDisplayFade|CGAcquireDisplayFadeReservation|CGRestorePermanentDisplayConfiguration|CGDisplaySetStereoOperation|CGConfigureDisplayStereoOperation` (expect none); `CGConfigureDisplayMirrorOfDisplay|CGBeginDisplayConfiguration` outside `Infrastructure/CoreGraphics` and `Infrastructure/VirtualDisplay` (lint error).

Wrong:
```swift
CGConfigureDisplayOrigin(config, virtualID, 0, 0)        // moves the user's arrangement; not undone on error
let token = … CGAcquireDisplayFadeReservation(5, &token); CGDisplayFade(token, 0.3, …)   // a throw before the fade-in leaves the panel black
```
Right:
```swift
// DisplayModeService: CGConfigureDisplayWithDisplayMode only. VirtualDisplayService: that plus CGConfigureDisplayMirrorOfDisplay(config, physical, virtualID | 0).
```

## Severity guide

| Severity | Classify here when… | Typical findings from this file |
|---|---|---|
| High | The user's monitor can end up blank, mirrored to nothing, on a mode that reverts, or stuck with a lingering virtual display, with no recovery path in the UI | Missing `Cancel` or `Cancel` after `Complete` (#1); `CGDisplaySetDisplayMode` or `.forSession` physical mode (#2); second owner or release-before-unmirror of a `CGVirtualDisplay`, a `terminationHandler` block (#7); unconditional virtual mode change or unbounded spin (#8); exit/sleep with mirrors active (#10); `/Library/Displays` written outside the installer or on reconnect (#12); origin/capture/fade/restore-all calls (#14) |
| Medium | A wrong but recoverable choice: the wrong mode is offered or picked, a stale object is compared, a state is misread for one refresh | Mode table read without the duplicate-low-res option or without the usability filter (#3); `CGDisplayMode` compared across copies or ids persisted (#4); framework type in Domain (#5); callbacks acted on without the `isApplying` guard or without re-enumeration (#6); mirror without `ensureNativeMode`/`restoreRateIfNeeded` (#9); `hasUsableHiDPI` counting 960×540@2x (#11); `takeUnretainedValue` or force-unwrapped `NSScreen` (#13) |
| Low | Diagnostics and polish | Verification that logs but does not throw (#1); `pendingOverrides` not cleared after the reconnect (#12); a `maxDisplays` constant lower than `CGGetOnlineDisplayList` could return on a hub (#13); a missing `dump-modes.swift` run in the verification notes |
