# Security rules — LiteDisplay code audit

**Scope.** LiteDisplay is a local-only display utility: no App Sandbox, hardened runtime on, ad-hoc signed, a single entitlement key (`com.apple.security.app-sandbox = false`), zero networking, zero telemetry, zero third-party code. It writes to exactly four places: `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-<hex>/DisplayProductID-<hex>` (as root, through `PrivilegedRunner`, after a click), `~/Library/Application Support/LiteDisplay/profiles.json`, its own `UserDefaults` (`settings` key, JSON) and two global user preferences (`AppleFontSmoothing`, `CGFontRenderingFontSmoothingDisabled`). It links one set of private CoreGraphics classes (`CGVirtualDisplay*`) weakly. This checklist keeps that contract true: entitlement minimalism, no network or process surface beyond the one `osascript` call, a privileged command built only from constants and quoted paths, verified writes, trustworthy persisted data, logging hygiene and a dependency-free supply chain. Apply to the whole Swift tree plus `CGVirtualDisplay.h`, `LiteDisplay.entitlements`, `Info.plist`, `project.yml`, `Makefile` and `scripts/`.

## 1. **Hardened runtime stays on and the entitlements file contains exactly one key: `app-sandbox` = false**

Hardened runtime blocks code injection, DYLD environment variables and unsigned executable memory; each extra entitlement (`allow-jit`, `disable-library-validation`, network client, device access) widens what a compromised process can do, and with no sandbox the entitlements file is the only machine-readable statement of what the app may touch. The app needs nothing: display configuration, `SMAppService`, `CFPreferences` and `osascript` work without entitlements.

Grep: `<key>com\.apple\.security\.` in `LiteDisplay.entitlements` (expect only `app-sandbox`); `ENABLE_HARDENED_RUNTIME: NO|allow-jit|disable-library-validation|allow-dyld-environment-variables|allow-unsigned-executable-memory|security\.network|security\.device|security\.files|personal-information` in `project.yml`, `project.pbxproj` and the entitlements.

Wrong:
```xml
<key>com.apple.security.app-sandbox</key><false/>
<key>com.apple.security.cs.disable-library-validation</key><true/>   <!-- any dylib may load into a process that runs osascript as root -->
<key>com.apple.security.network.client</key><true/>                 <!-- there is no network code -->
```
Right:
```xml
<key>com.apple.security.app-sandbox</key><false/>
```
Verify the built product, not only the source: `codesign -d --entitlements :- "${TMPDIR}LiteDisplay-DerivedData/Build/Products/Debug/LiteDisplay.app"` and `codesign -dv --verbose=2 … 2>&1 | grep -i runtime`.

## 2. **No networking, no telemetry, no crash uploaders**

The promise in the Settings pane is "Sem rede, sem telemetria: tudo acontece no seu Mac". One `URLSession` call for an update check makes the app a network client, triggers firewall prompts and falsifies that text. Diagnostics stay local: `os.Logger` and the crash reports the user can share by hand.

Grep: `URLSession|URLRequest|NWConnection|NWListener|NWBrowser|import Network|CFSocket|CFStream|NSURLConnection|NetService|SCNetworkReachability|WKWebView|Analytics|Crashlytics|Sentry|Firebase|Mixpanel|Amplitude|TelemetryDeck|MXMetricManager|MetricKit|CKContainer`; `https?://` outside comments.

Wrong:
```swift
let (data, _) = try await URLSession.shared.data(from: URL(string: "https://example.org/latest.json")!)
MXMetricManager.shared.add(self)
```
Right:
```swift
Log.app.info("LiteDisplay launched")                                    // unified log only; no outbound action anywhere
```

## 3. **Process spawning happens in `PrivilegedRunner.execute` only, and it runs `/usr/bin/osascript -e` only**

A second place that spawns a process is a second privilege boundary to audit forever; a shell string built anywhere else will eventually interpolate a display name. `PrivilegedRunner` is the whole surface: absolute path to `osascript`, arguments `["-e", script]`, no `sudo`, no `AuthorizationExecuteWithPrivileges`, no `SMJobBless`/privileged helper, no LaunchDaemon, no `NSAppleScript`, no `system()`/`popen()`. Dynamic code loading (`dlopen`, `dlsym`, `Bundle.load`) is forbidden outright; the private virtual display classes are reached through normal weak linking plus `NSClassFromString`, which is a lookup, not a load.

Grep: `Process\(|NSTask|posix_spawn|\bsystem\(|popen\(|execv|NSAppleScript|osascript|with administrator privileges` outside `Infrastructure/Override/PrivilegedRunner.swift`; `\bsudo\b|SMJobBless|AuthorizationExecute|AuthorizationCreate|LaunchDaemons|dlopen|dlsym|Bundle\([^)]*\)\.load` anywhere.

Wrong:
```swift
let p = Process(); p.launchPath = "/usr/bin/sudo"; p.arguments = ["cp", staged, dest]   // no dialog, needs a sudoers entry
try SMAppService.daemon(plistName: "br.com.asoft.LiteDisplay.helper.plist").register()   // persistent root helper
```
Right:
```swift
// PrivilegedRunner: the only Process in the app, one command, one system dialog
process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
process.arguments = ["-e", "do shell script \(Self.appleScriptLiteral(command)) with administrator privileges with prompt \(Self.appleScriptLiteral(prompt))"]
```

## 4. **The privileged command is assembled from constants and `shellQuoted` paths; the only variable inputs are validated hex ids and a staged path under `temporaryDirectory`**

The command string runs as root inside `/bin/sh`. Display names come from EDID and are attacker-influenced (a monitor can report any string); profile names are user text. `HiDPIOverrideInstaller.installCommand` uses absolute binaries (`/bin/mkdir`, `/bin/cp`, `/usr/sbin/chown`, `/bin/chmod`), single-quotes every path through `PrivilegedRunner.shellQuoted`, and the paths derive from `HiDPIOverrideProfile.installPath`, whose only inputs are `vendorHex`/`productHex` checked by `hasValidIdentifiers` (`^[0-9a-f]{1,8}$`, non-zero). The AppleScript layer escapes the command and the prompt again with `appleScriptLiteral`. The prompt is a fixed localized sentence.

Grep: `installCommand|shellQuoted|appleScriptLiteral`; string interpolation inside `installCommand` other than `directory|destination|backup|source`; `display\.name|profile\.name` within `Infrastructure/Override/`.

Wrong:
```swift
"/bin/cp \(stagedPath) /Library/Displays/Contents/Resources/Overrides/\(display.name)"   // unquoted; EDID string reaches root sh
let prompt = "Install override for \(display.name)"                                        // unescaped quotes break the literal
```
Right:
```swift
guard profile.hasValidIdentifiers else { throw .invalidIdentifier }
let destination = PrivilegedRunner.shellQuoted(profile.installPath)          // '/Library/Displays/.../DisplayVendorID-472/DisplayProductID-746'
return ["/bin/mkdir -p \(directory)", "if [ -f \(destination) ]; then /bin/cp \(destination) \(backup); fi",
        "/bin/cp \(source) \(destination)", "/usr/sbin/chown root:wheel \(destination)", "/bin/chmod 644 \(destination)"].joined(separator: " && ")
```

## 5. **What was installed as root is read back and compared byte-for-byte; a previous file is backed up first**

The app cannot see what happened inside the root shell beyond an exit status. `HiDPIOverrideInstaller.verify` re-reads `profile.installPath`, decodes it with `HiDPIOverrideProfile.decode`, and checks vendor id, product id and the entry set; any mismatch is `overrideVerificationFailed` with a reason the banner shows. The `.bak` copy keeps a vendor-supplied override recoverable. `scripts/verify-override.sh <vendorHex> <productHex>` is the manual equivalent.

Grep: `verify\(profile\)` after `runner.run`; `\.bak`; `decode\(` in `HiDPIOverrideProfile`.

Wrong:
```swift
try await runner.run(command, prompt: prompt)
Log.override.info("Installed")                      // trusts the exit status; a wrong file stays until the next reconnect
```
Right:
```swift
try await runner.run(command, prompt: prompt)
try verify(profile)                                 // missing / invalid / different ids / different entries → typed error
```

## 6. **Staging uses a private `0700` directory under `FileManager.default.temporaryDirectory`, an atomic write, mode `0644`, and `defer` cleanup**

The staged file is what root copies; a predictable path in `/tmp` lets another local user swap the plist between the write and the copy. The per-user temporary directory is private, the directory is created `0700`, the file name is fixed (`DisplayProductID-<hex>`) inside a `UUID` folder, the write is `.atomic`, and the file is chmod'ed `0644` so the copy's mode is right before `chown root:wheel`.

Grep: `"/tmp|NSTemporaryDirectory\(\)|/var/tmp` (expect none); `temporaryDirectory` followed by `posixPermissions: 0o700` and `options: [.atomic]`.

Wrong:
```swift
let staged = URL(fileURLWithPath: "/tmp/\(profile.fileName)")       // shared, predictable, replaceable
try data.write(to: staged)
```
Right:
```swift
let stagingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("LiteDisplay-override-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
try data.write(to: stagedFile, options: [.atomic])
try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: stagedFile.path)
```

## 7. **The app process writes only to Application Support/LiteDisplay (0700, atomic) and `UserDefaults`; `/Library` is written only by the root command**

Without a sandbox the process can write anywhere, so the discipline lives in review. `ProfileStore.persist` creates `~/Library/Application Support/LiteDisplay` with `0700`, encodes with sorted keys and writes `.atomic`; `SettingsStore` writes one JSON blob under the `settings` key. Nothing else calls `write(to:)`, `createDirectory`, `moveItem`, `copyItem` or `removeItem` except the installer's staging (rule 6). No writes to `~/Library/Displays`, `~/Library/Preferences/com.apple.windowserver*`, `/Library/Preferences`, and no `defaults write` through a process.

Grep: `\.write\(to:|createDirectory\(|moveItem\(|copyItem\(|removeItem\(|FileManager\.default\.\w+\(atPath` outside `Infrastructure/Storage/` and `Infrastructure/Override/`; `write\(to:` without `options: [.atomic]`; `UserDefaults\.` outside `Infrastructure/Storage/` and `App/AppContainer.swift`.

Wrong:
```swift
try encoder.encode(profiles).write(to: fileURL)                               // partial file on crash → profiles lost at next launch
UserDefaults(suiteName: "com.apple.windowserver")?.set(…, forKey: "DisplayAnyUserSets")   // window server state by hand
```
Right:
```swift
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
try encoder.encode(profiles).write(to: fileURL, options: [.atomic])
```

## 8. **Persisted JSON is untrusted: profiles are filtered by `Profile.isValid`, settings fall back to defaults, and stored sizes only ever *select* from the live mode table**

Anyone can edit `profiles.json` or `defaults write` the settings blob. `ProfileStore.load` decodes and keeps only `isValid` entries (non-empty name ≤ 60 characters, at least one display); `SettingsStore.load` returns `AppSettings()` on any decode error and logs it. `DisplaySettings.size`/`refreshRate` and `Profile.displays` are never handed to CoreGraphics: `SetSharpnessUseCase.selectMode` resolves them through `ModeSelection.mode(in: display.modes, …)` against the current snapshot, so an absurd stored size yields `modeUnavailable`, never a transaction. Mode ids (`ioDisplayModeID`) are never persisted because they change per connection.

Grep: `JSONDecoder\(\)\.decode` without `isValid|catch`; `CGConfigureDisplayWithDisplayMode` reachable from a stored value without `DisplayModeCatalog.cgMode(matching:`; `Codable` on `DisplayMode` used in `Profile|AppSettings` fields.

Wrong:
```swift
struct DisplaySettings: Codable { var modeID: Int32 }                         // stale per connection, unverifiable
let cgMode = DisplayModeCatalog.cgModes(for: id).first { $0.ioDisplayModeID == stored.modeID }!   // force unwrap on untrusted data
```
Right:
```swift
struct DisplaySettings: Codable, Sendable, Hashable { var method: SharpnessMethod; var size: DisplaySize?; var refreshRate: Double? }
guard let mode = ModeSelection.mode(in: display.modes, size: size, hiDPI: true, preferredRate: rate) else { throw .modeUnavailable }
```

## 9. **The override plist is generated from `HiDPIOverrideProfile` only: bounded sizes, fixed byte layout, decodable**

The file lands in a root-owned system directory and is parsed by the window server at connection time. `scaledSizes` is bounded (from the native width down to `minimumWidth` 1280 in steps of 16, aspect preserved), the entries are `encode1x` (8 bytes) and `encodeHiDPI` (16 bytes with flags `0x00000009`, `0x00200000`), the plist has exactly three keys, and `decode` round-trips it. Hand-written plists, extra keys (`DisplayProductName`, EDID blobs, `IODisplayEDID`), or sizes beyond the panel's pixel size are findings.

Grep: `scale-resolutions|DisplayVendorID|DisplayProductID` outside `HiDPIOverrideProfile.swift`; `PropertyListSerialization` outside Domain and the installer; `stride\(from:` bounds in `scaledSizes`.

Wrong:
```swift
plist["IODisplayEDID"] = edidData                                            // replaces the panel's identity for the window server
plist["scale-resolutions"] = [encodeHiDPI(DisplaySize(width: 7680, height: 4320))]   // beyond the panel; the display may not come up
```
Right:
```swift
func propertyList() -> [String: Any] {
    ["DisplayVendorID": Int(vendorID), "DisplayProductID": Int(productID), Self.scaleResolutionsKey: entries]
}
```

## 10. **Global preferences: `FontSmoothingService` only, two keys, constant values, current user, synchronize checked**

`CFPreferencesSetValue` with `kCFPreferencesAnyApplication` edits `~/Library/Preferences/.GlobalPreferences*.plist`, which every app reads. Only the two font-smoothing keys are written, with constant values (3/2 and `false`), in the `kCFPreferencesCurrentUser` domain (`AnyUser` would need root and affect every account), and both `CFPreferencesSynchronize` results are checked so a failed write surfaces as `preferencesFailed`. `isStrongSmoothingEnabled` reads the live value; no cached flag.

Grep: `CFPreferences(Set|Copy|Synchronize)` outside `Infrastructure/System/FontSmoothingService.swift`; `kCFPreferencesAnyUser`; `CFPreferencesSetAppValue|CFPreferencesSetMultiple`; keys other than `AppleFontSmoothing|CGFontRenderingFontSmoothingDisabled`.

Wrong:
```swift
CFPreferencesSetValue("AppleFontSmoothing" as CFString, weight, kCFPreferencesAnyApplication, kCFPreferencesAnyUser, kCFPreferencesCurrentHost)   // fails silently without root
CFPreferencesSetValue("NSGlobalDomain" as CFString, …)                       // unrelated key in the global domain
```
Right:
```swift
CFPreferencesSetValue(Self.smoothingKey, weight, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
guard CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) else { throw .preferencesFailed }
```

## 11. **Logging goes through `Log.*` (`os.Logger`); display names, serials, user paths and privileged stderr are `.private`; no `print`/`NSLog`**

`print`/`NSLog` write unredacted text to stdout and the unified log, readable by any local process and included in sysdiagnoses. `Logger` redacts interpolated strings by default; mark sensitive values `.private` explicitly so a later "make it public" edit shows in review. Numeric display ids, mode geometry, error codes and the override install path (derived from vendor/product hex only) may be `.public`. The stderr of the privileged command can contain the staged path and AppleScript diagnostics: `.private`.

Grep: `\bprint\(|NSLog\(|debugPrint\(|dump\(|os_log\(` (expect none); `Log\.\w+\.\w+\(.*\\\((\w+\.)?(name|localizedName|path|url|stderr|serial)` without `privacy:`; `privacy: \.public` next to a string value.

Wrong:
```swift
print("Created virtual display for \(display.name)")
Log.override.error("Privileged command failed: \(outcome.stderr)")          // default redaction; a later .public edit is invisible
```
Right:
```swift
Log.virtualDisplay.info("Created virtual display \(virtualID) for display \(display.id)")        // ids only
Log.override.error("Privileged command failed: \(outcome.stderr, privacy: .private)")
```

## 12. **Private API stays in `Infrastructure/VirtualDisplay`: `weak_import` declarations, `NSClassFromString` guard, graceful absence**

`CGVirtualDisplay*` are undocumented classes. `CGVirtualDisplay.h` marks each `__attribute__((weak_import))` so the binary launches on a macOS that drops them; `VirtualDisplayService.isAvailable` checks all four names with `NSClassFromString` before any use, and the UI hides the method when it is false (`availableMethods` in `SharpnessSection`, `isVirtualDisplayAvailable` in the menu). Declaring extra private selectors, calling `performSelector` on them, or copying the header's declarations into another file widens the private surface.

Grep: `CGVirtualDisplay` outside `Infrastructure/VirtualDisplay/`; `weak_import` in `CGVirtualDisplay.h` (expect four); `NSClassFromString|performSelector|NSSelectorFromString|objc_getClass|class_getInstanceMethod`.

Wrong:
```objc
@interface CGVirtualDisplay : NSObject   // no weak_import: dyld aborts launch on a macOS without the class
```
```swift
let cls = NSClassFromString("CGVirtualDisplay") as? NSObject.Type; cls?.perform(NSSelectorFromString("_privateReset"))
```
Right:
```objc
__attribute__((weak_import)) @interface CGVirtualDisplay : NSObject … @end
```
```swift
let isAvailable: Bool = VirtualDisplayService.requiredClasses.allSatisfy { NSClassFromString($0) != nil }
guard isAvailable else { throw .virtualDisplayUnavailable }
```

## 13. **Login item through `SMAppService.mainApp` only; relaunch through `NSWorkspace`, not a shell**

`SMAppService.mainApp.register()` is the sanctioned way to open at login and needs no helper; `SMJobBless`, `LSSharedFileList`, a LaunchAgent plist or an AppleScript "login items" edit are either deprecated, privileged or both. `AppContainer.relaunch()` opens `Bundle.main.bundleURL` with `createsNewApplicationInstance` and terminates; `open -n` through a process would be a second spawn site.

Grep: `SMAppService\.(daemon|agent|loginItem)|SMJobBless|LSSharedFileList|LaunchAgents|openApplication\(at:` (expect `mainApp` and one `openApplication` in `AppContainer`).

Wrong:
```swift
Process.launchedProcess(launchPath: "/usr/bin/open", arguments: ["-n", Bundle.main.bundlePath])   // process spawn outside PrivilegedRunner
```
Right:
```swift
let configuration = NSWorkspace.OpenConfiguration(); configuration.createsNewApplicationInstance = true
NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in … Task { @MainActor in NSApp.terminate(nil) } }
```

## 14. **Zero third-party dependencies, pinned toolchain, build products outside the checkout**

Every package would run inside the hardened process that spawns a root shell. `project.yml` pins `xcodeVersion`; `swiftlint`/`swiftformat` come from Homebrew and their versions are reported by the audit script. `Makefile`, `scripts/release.sh` and the audit pass `-derivedDataPath` under `$TMPDIR`: a `DerivedData/`, `build/` or `.app` inside the repository ends up in a cloud-synced folder and in the next `git add`. Imports stay inside the Apple set.

Grep: `XCRemoteSwiftPackageReference|XCLocalSwiftPackageReference|packages:` in `project.yml`/`project.pbxproj`; `Package\.swift|Podfile|Cartfile|\.xcframework`; `^import ` not in `Foundation|AppKit|SwiftUI|CoreGraphics|CoreFoundation|ServiceManagement|OSLog|Observation|Testing|Darwin`; `find . -maxdepth 2 \( -name DerivedData -o -name '*.app' -o -name build \)`.

Wrong:
```swift
import LaunchAtLogin                       // SPM package wrapping SMAppService
```
```make
xcodebuild … -derivedDataPath ./DerivedData   # inside the checkout
```
Right:
```swift
import ServiceManagement                   // SMAppService.mainApp directly
```
```make
DERIVED ?= $(or $(TMPDIR),/tmp)/LiteDisplay-DerivedData
```

## 15. **`Info.plist` declares a menu-bar app with no device usage strings and no sudden termination**

`LSUIElement = true` keeps the app out of the Dock; there is no `NS*UsageDescription` because no TCC-gated capability is used (a camera, microphone, location or Apple Events string signals code that should not exist); `NSSupportsSuddenTermination = false` and `NSSupportsAutomaticTermination = false` give `applicationShouldTerminate` time to unmirror. `CFBundleDevelopmentRegion` is `pt-BR` with `en` in `CFBundleLocalizations`.

Grep: `UsageDescription` in `Info.plist` and `INFOPLIST_KEY_` in `project.yml` (expect none); `LSUIElement`, `NSSupportsSuddenTermination`.

Wrong:
```xml
<key>NSAppleEventsUsageDescription</key><string>Automation</string>   <!-- nothing targets another app -->
<key>NSSupportsSuddenTermination</key><true/>                          <!-- killed mid-unmirror -->
```
Right:
```xml
<key>LSUIElement</key><true/>
<key>NSSupportsSuddenTermination</key><false/>
```

## Severity guide

| Severity | Classify here when… | Typical findings from this file |
|---|---|---|
| High | Data can leave the Mac, code can be executed or loaded dynamically, root runs something not built from constants, the privilege surface grows, or a system or user file outside the four allowed locations can be written | Networking or telemetry (#2); a second process spawn, `sudo`, helper tool or `dlopen` (#3, #13); unquoted or name-derived text in the privileged command (#4); extra entitlement or hardened runtime off (#1); writes to `/Library`, `~/Library/Displays` or window-server prefs from the app process (#7); `AnyUser` or unrelated global preference keys (#10); private selectors or missing `weak_import` (#12); third-party package (#14) |
| Medium | A profile, setting or override can be corrupted or left in a bad state, or private details reach the log, without crossing a trust boundary | Install without read-back verification (#5); staging in `/tmp` or without `0700`/atomic (#6); non-atomic store writes (#7); persisted ids or unvalidated JSON reaching a transaction (#8); oversized or extra-key override plist (#9); `print` or unannotated name/stderr logging (#11); build products inside the checkout (#14); a usage string for a capability that is not used (#15) |
| Low | Hygiene with no exploit path and no data loss | `.public` on numeric ids (#11); a pinned tool version drifting from `project.yml` (#14); `Info.plist` wording (#15); a missing `.bak` when no previous file existed (#5) |
