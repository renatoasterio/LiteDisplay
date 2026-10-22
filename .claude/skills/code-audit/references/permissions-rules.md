# Permissions rules — LiteDisplay code audit

**Scope.** LiteDisplay asks for no TCC permission (no camera, microphone, screen recording, accessibility or automation). Its privilege and permission surfaces are different and system-wide: (a) one administrator authentication through `osascript … with administrator privileges` to copy a display override into `/Library/Displays`; (b) login-item registration through `SMAppService.mainApp`; (c) two global user preferences written with `CFPreferences`; (d) display configuration transactions committed `.permanently`, which the window server remembers for every future session; (e) a private virtual display API. The non-negotiable rules: every privileged action goes through `Infrastructure/Override/PrivilegedRunner.swift` and happens only in response to a click ("Habilitar HiDPI neste monitor…"), never at launch, on reconnect or in a retry; nothing persistent runs as root; login item and global preferences change only from the Settings toggles; every denied or failed state has an explanation and a way out. Apply to `Infrastructure/Override`, `Infrastructure/System`, `Domain/UseCases`, the view models, `AppContainer`, `Info.plist` and the entitlements.

## 1. **All privilege escalation goes through `PrivilegedExecuting` → `PrivilegedRunner`; Domain and Features see only the protocol**

One choke point makes "never without a click" auditable with a single grep and keeps `Process`, AppleScript strings and shell quoting out of use cases and views. `EnableHiDPIOverrideUseCase` talks to `OverrideInstalling`; `HiDPIOverrideInstaller` talks to `PrivilegedExecuting`; tests inject `FakePrivilegedExecutor` and assert on the command text.

Grep: `with administrator privileges|osascript|Process\(` outside `PrivilegedRunner.swift` (every hit is a finding); `PrivilegedRunner\(` outside `AppContainer.live()`.

Wrong:
```swift
// Features/Monitors/MonitorsViewModel.swift
func installOverride(for display: DisplaySnapshot) async {
    try? await PrivilegedRunner().run("cp \(path) /Library/Displays/…", prompt: "…")   // runner used from a view model with a hand-built command
}
```
Right:
```swift
// Domain/Protocols/PrivilegedExecuting.swift
protocol PrivilegedExecuting: Sendable { func run(_ command: String, prompt: String) async throws(LiteDisplayError) }
// App/AppContainer.swift
overrideInstaller: HiDPIOverrideInstaller(runner: PrivilegedRunner())
```

## 2. **The administrator prompt appears only inside the click handler of the override button, never at launch, on reconnect, after wake or in `ReapplyOnConnectUseCase`**

A password dialog the user did not cause is the fastest way to be treated as malware, and an unattended prompt on reconnect can steal focus from a full-screen app. The only path is `OverrideCard` → `MonitorsViewModel.installOverride(for:)` → `EnableHiDPIOverrideUseCase.execute` → `HiDPIOverrideInstaller.install`. `ReapplyOnConnectUseCase`, `resumeVirtualDisplays`, `applicationDidFinishLaunching`, `.onAppear` and `.task` never reach the installer.

Grep: `installer\.install|overrideInstaller\.execute|installOverride\(` — each call site must be a `Button` action; `install` in `ReapplyOnConnectUseCase|AppContainer|AppDelegate|\.onAppear|\.task`.

Wrong:
```swift
func execute(displayID: UInt32) async throws(LiteDisplayError) -> Bool {       // ReapplyOnConnectUseCase
    if !display.hasUsableHiDPI { _ = try await installer.install(profile) }   // prompt on every cable plug
}
```
Right:
```swift
Button("Habilitar HiDPI neste monitor…") {
    Task { await container.monitors.installOverride(for: display) }           // one click, one prompt
}
.buttonStyle(.vibrant)
```

## 3. **One prompt per click: cancellation is `privilegeDenied`, failures are typed, nothing retries or caches "authorized"**

`osascript` reports "User canceled" as error `-128` on stderr; the runner maps it to `privilegeDenied` ("Clique de novo e informe a senha") and any other non-zero status to `privilegedCommandFailed(stderr)`. A loop that re-runs on failure shows the dialog repeatedly; a cached "already authorized" flag is meaningless because `do shell script with administrator privileges` authenticates per call (macOS caches the credential for about five minutes by itself).

Grep: `for .* in .*run\(|while .*run\(|retry` around `runner.run`; `@AppStorage\(".*(granted|authorized|admin)|forKey: ".*(granted|authorized)"`.

Wrong:
```swift
for _ in 0..<3 { if (try? await runner.run(command, prompt: prompt)) != nil { break } }   // three dialogs for one cancel
defaults.set(true, forKey: "adminGranted")
```
Right:
```swift
guard outcome.status == 0 else {
    if outcome.stderr.contains(Self.userCancelled) { throw .privilegeDenied }                 // "-128"
    throw .privilegedCommandFailed(outcome.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
}
```

## 4. **The root command is the fixed five-step sequence; nothing destructive, nothing recursive, nothing that touches the window server**

What runs as root is `mkdir -p`, a `.bak` copy of any existing file, `cp`, `chown root:wheel`, `chmod 644` — all with absolute binaries and single-quoted paths. `rm -rf`, `chmod -R`, `killall WindowServer`, `kextcache`, `reboot`, `defaults write` or anything under `/System` turns a display utility into a system administration tool. The prompt text is a fixed localized sentence naming LiteDisplay and the action.

Grep: `rm -rf|chmod -R|chown -R|killall|kextcache|reboot|shutdown|launchctl|defaults write|/System/` in `Infrastructure/Override/`; `installCommand` lines outside the five known ones.

Wrong:
```swift
"/bin/rm -rf \(directory) && /bin/cp \(source) \(destination) && /usr/bin/killall WindowServer"   // logs the user out
```
Right:
```swift
["/bin/mkdir -p \(directory)",
 "if [ -f \(destination) ]; then /bin/cp \(destination) \(backup); fi",
 "/bin/cp \(source) \(destination)",
 "/usr/sbin/chown root:wheel \(destination)",
 "/bin/chmod 644 \(destination)"].joined(separator: " && ")
```

## 5. **No persistent privilege: no helper tool, daemon, agent, `sudoers` entry or setuid binary; the only root-owned artifact is a data file**

`SMJobBless`, `SMAppService.daemon`, a LaunchDaemon plist, `AuthorizationExecuteWithPrivileges` or an XPC helper keep root reachable after the click ends and need their own code-signing requirements, which an ad-hoc signed app cannot satisfy honestly. The override plist is parsed by the window server; it is data, not code, and it is the only thing LiteDisplay leaves on the system as root.

Grep: `SMJobBless|SMAppService\.(daemon|agent)|LaunchDaemons|AuthorizationExecuteWithPrivileges|AuthorizationCreate|NSXPCConnection|xpc_connection|setuid|sudoers|/etc/`.

Wrong:
```swift
let connection = NSXPCConnection(machServiceName: "br.com.asoft.LiteDisplay.helper", options: .privileged)   // root helper for life
```
Right:
```swift
// Nothing persistent. The whole root session is one `do shell script … with administrator privileges` call in PrivilegedRunner.
```

## 6. **Login item: `SMAppService.mainApp` toggled from Settings only; `requiresApproval` gets a button to `openSystemSettingsLoginItems()`; status is read live**

Registering at launch is a permission grab the user did not make. `LaunchAtLoginService.isEnabled`/`requiresApproval` read `service.status` each time (`SettingsViewModel.refresh()` on appear and after every change); macOS 13+ may put the item in "requires approval", and the only fix is System Settings › General › Login Items, so the view shows "Aprovar em Ajustes do Sistema…". Errors from `register()`/`unregister()` become `loginItemFailed`. Note for Debug builds: `SMAppService` keys the item to the bundle path, so a build under `$TMPDIR` registers a path that disappears; `make install` copies the app to `/Applications` for a stable path.

Grep: `service\.register\(\)` call sites (expect `setEnabled` only); `register\(\)` in `applicationDidFinishLaunching|start\(\)|init`; `requiresApproval` in a view with `openSystemSettingsLoginItems`; `var launchAtLogin = ` cached without `refresh()`.

Wrong:
```swift
func applicationDidFinishLaunching(_ note: Notification) { try? SMAppService.mainApp.register() }   // silent, unasked
if status == .requiresApproval { try? service.register() }                                           // no-op; user sees nothing
```
Right:
```swift
Toggle(isOn: Binding(get: { preferences.launchAtLogin }, set: { preferences.setLaunchAtLogin($0) })) { Text("Iniciar no login") }
if preferences.loginRequiresApproval {
    Button("Aprovar em Ajustes do Sistema…") { preferences.openLoginItemsSettings() }               // SMAppService.openSystemSettingsLoginItems()
}
```

## 7. **Global preference writes happen only in `FontSmoothingService`, only from the Settings toggle, only for the two font-smoothing keys, in the current-user domain**

`AppleFontSmoothing` changes text rendering in every app the user opens afterwards; it is a user decision, not a side effect of choosing a sharpness method. The service reads back the live value (`isStrongSmoothingEnabled`) rather than caching, writes constants (3 or 2, `false`), uses `kCFPreferencesCurrentUser` (never `AnyUser`, which needs root), and checks both `CFPreferencesSynchronize` results.

Grep: `CFPreferences(Set|Copy|Synchronize)` outside `FontSmoothingService.swift`; `setStrongSmoothing\(` call sites (expect `SettingsViewModel.setStrongFontSmoothing` only); `setStrongSmoothing` inside `SetSharpnessUseCase|ApplyProfileUseCase|ReapplyOnConnectUseCase`.

Wrong:
```swift
case .hiDPI:
    try fontSmoothing.setStrongSmoothing(true)      // sharpness toggle silently rewrites a global preference
```
Right:
```swift
func setStrongFontSmoothing(_ enabled: Bool) {       // SettingsViewModel, bound to the "Suavização de fontes mais forte" toggle
    do { try fontSmoothing.setStrongSmoothing(enabled); error = nil } catch { self.error = error }
    refresh()
}
```

## 8. **Display transactions run only after a user action or the user-enabled "Restaurar ao conectar" setting; the reconnect path never prompts and never installs**

A `.permanently` configuration survives the app and the session: the window server restores it on every reconnect of that panel. That is wanted for an explicit choice and for `reapplyOnConnect` (default on, visible in Settings as "Restaurar ao conectar", persisted in `AppSettings`), and wrong for anything else. `ReapplyOnConnectUseCase` checks the setting first, applies a profile marked `applyOnConnect` or the last `DisplaySettings`, and skips when `isSatisfied(by:)` to avoid a needless flash. It never installs an override, never creates a virtual display the user had turned off, and runs with `isApplying` set so the app's own callbacks are ignored.

Grep: `sharpness\.execute|modes\.apply\(` call sites — each must be a use case reached from a view model action, `ReapplyOnConnectUseCase`, `ApplyProfileUseCase` or `resumeVirtualDisplays`; `settings\.reapplyOnConnect` checked at the top of `ReapplyOnConnectUseCase.execute`.

Wrong:
```swift
func handle(_ change: DisplayChange) {
    if case let .added(id) = change { Task { try? await sharpness.execute(.init(display: …, method: .hiDPI)) } }   // ignores the setting, ignores isApplying
}
```
Right:
```swift
guard settings.settings.reapplyOnConnect, let display = displays.externalDisplays().first(where: { $0.id == displayID }) else { return false }
guard let wanted = fromProfile ?? settings.settings.displays[display.persistentID] else { return false }
if wanted.isSatisfied(by: display) { return false }
try await sharpness.execute(.init(display: display, method: wanted.method, size: wanted.size, refreshRate: wanted.refreshRate))
```

## 9. **No TCC-gated API anywhere: no screen capture, accessibility, event taps, input monitoring, or AppleScript that targets another app**

`osascript -e 'do shell script …'` needs no Automation permission because it targets no application; `tell application "System Events"` would trigger the Automation prompt and need `NSAppleEventsUsageDescription`. `CGRequestScreenCaptureAccess`, `AXIsProcessTrusted`, `CGEvent.tapCreate`, `SCShareableContent`, `IOHIDManager` and `AVCaptureDevice` each add a Privacy & Security toggle the app has no business asking for. The presence of any usage-description key in `Info.plist` is a finding.

Grep: `tell application|CGRequestScreenCaptureAccess|CGPreflightScreenCaptureAccess|AXIsProcessTrusted|AXUIElement|CGEvent\.tapCreate|SCShareableContent|SCStream|IOHIDManager|AVCaptureDevice|CLLocationManager|UsageDescription`.

Wrong:
```swift
let script = "tell application \"System Events\" to tell process \"SystemUIServer\" …"   // Automation prompt + NSAppleEventsUsageDescription
```
Right:
```swift
let script = "do shell script \(Self.appleScriptLiteral(command)) with administrator privileges with prompt \(Self.appleScriptLiteral(prompt))"
```

## 10. **Every `LiteDisplayError` has a `recoverySuggestion`, and the stuck states have a button**

Once the prompt is cancelled, the login item needs approval, the virtual display lingers or the override does not verify, text alone is not enough. `ErrorBanner` shows `errorDescription` + `recoverySuggestion`; `MonitorDetailView` adds "Reabrir o LiteDisplay" (`container.relaunch()`) for `virtualDisplayLingering`; `SettingsView` adds "Aprovar em Ajustes do Sistema…" for `loginRequiresApproval`; after an install the notice says to reconnect the monitor and `pendingOverrides` keeps the card in its "installed" state until `hasUsableHiDPI` becomes true. A new error case without a suggestion, or a `catch` that swallows a `LiteDisplayError` into `nil`, leaves the user guessing.

Grep: `case \w+` in `LiteDisplayError` vs `recoverySuggestion` switch coverage (the switch must be exhaustive without `default`); `try\?` on a call that throws `LiteDisplayError` in a view model; `virtualDisplayLingering` paired with `relaunch\(\)`.

Wrong:
```swift
case .virtualDisplayLingering: return nil                                   // no way out shown
try? await virtualDisplays.deactivate(for: display.id)                      // lingering state swallowed; UI shows success
```
Right:
```swift
case .virtualDisplayLingering: String(localized: "Reabra o LiteDisplay para removê-la.")
if error == .virtualDisplayLingering { Button("Reabrir o LiteDisplay") { container.relaunch() } }
```

## 11. **The private virtual display API degrades, never crashes: guarded by `isAvailable`, hidden in the UI when absent**

The classes are private, so they may vanish in a macOS update. `weak_import` keeps the binary loadable; `VirtualDisplayService.isAvailable` (`NSClassFromString` for all four names) gates `activate`, `SetSharpnessUseCase` throws `virtualDisplayUnavailable` ("Use o modo HiDPI nativo"), `MonitorsViewModel.isVirtualDisplayAvailable` hides the method card and disables the menu toggle when the panel has no usable HiDPI either. Calling the classes without the guard, or showing the method when unavailable, is a finding.

Grep: `CGVirtualDisplay(Descriptor|Settings|Mode)?\(` preceded by `guard isAvailable|guard virtualDisplays.isAvailable` in the same function; `isVirtualDisplayAvailable` used in `SharpnessSection` and `MenuDisplayRow`.

Wrong:
```swift
let descriptor = CGVirtualDisplayDescriptor()        // unresolved weak symbol → crash on a macOS without the class
```
Right:
```swift
guard isAvailable else { throw .virtualDisplayUnavailable }
let descriptor = CGVirtualDisplayDescriptor()
```

## Severity guide

| Severity | Classify here when… | Typical findings from this file |
|---|---|---|
| High | Root can run without a click, more than once per click, or with a command outside the fixed sequence; privilege persists; a TCC prompt or usage key appears; a transaction runs without user intent | Privileged call outside `PrivilegedRunner` or from reconnect/launch/wake (#1, #2); retry loop or cached authorisation (#3); destructive or recursive root command (#4); helper tool, daemon, XPC or `sudoers` (#5); login item registered at launch (#6); `AnyUser` or sharpness-driven global preference write (#7); reconnect path ignoring `reapplyOnConnect` or installing overrides (#8); any TCC-gated API or `tell application` (#9); unguarded private class use (#11) |
| Medium | The user can get stuck or misled, but no privilege is misused | `LiteDisplayError` case without recovery suggestion, lingering/approval state without a button, swallowed typed error (#10); `requiresApproval` ignored or status cached (#6); unnecessary flash because `isSatisfied(by:)` is skipped (#8); virtual display method shown when `isAvailable` is false (#11) |
| Low | Wording or polish | Prompt text that does not name the action (#2); suggestion text that names the wrong Settings pane (#10); Debug build registering a `$TMPDIR` path without the `/Applications` note (#6) |
