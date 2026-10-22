# LiteDisplay architecture

## Layers

```
┌──────────────────────────────────────────────────────────────────────┐
│ Features (SwiftUI views, @MainActor @Observable view models)          │
│   MainWindow · Monitors · Profiles · Settings · MenuBar               │
├──────────────────────────────────────────────────────────────────────┤
│ Infrastructure                                                        │
│   CoreGraphics · VirtualDisplay · Override · System · Storage         │
├──────────────────────────────────────────────────────────────────────┤
│ Domain (models · protocols · use cases) — Foundation only             │
└──────────────────────────────────────────────────────────────────────┘
            App/AppContainer wires concrete services into protocols
```

- **Domain** owns the vocabulary: `DisplayMode`, `DisplaySize`, `DisplaySnapshot`, `SharpnessMethod`,
  `DisplaySettings`, `Profile`, `AppSettings`, `HiDPIOverrideProfile`, `LiteDisplayError`, and the protocols
  (`DisplayProviding`, `DisplayModeApplying`, `VirtualDisplayControlling`, `OverrideInstalling`,
  `PrivilegedExecuting`, `FontSmoothingControlling`, `LoginItemControlling`, `SettingsStoring`, `ProfileStoring`).
  `ModeSelection` holds the pure rules (native mode, HiDPI candidates, curated ladder, refresh rates). Use cases
  compose protocols: `SetSharpnessUseCase` (standard / HiDPI / virtual), `ChangeResolutionUseCase`,
  `ApplyProfileUseCase`, `SaveProfileUseCase`, `ReapplyOnConnectUseCase`, `EnableHiDPIOverrideUseCase`.
- **Infrastructure** implements the protocols, one folder per system area so framework quirks stay contained.
- **Features** are vertical slices. A view model receives protocols/use cases in its initializer and exposes
  observable state; views never talk to Infrastructure.
- **App** contains the scenes (`Window` + `MenuBarExtra`), `AppDelegate` (lifecycle, clean shutdown) and
  `AppContainer` (composition root, sleep/wake handling).

## How sharpness works

| Method | Mechanism | Persistence |
|---|---|---|
| `standard` | `DisplayModeService.apply` with the panel's native 1x mode (`kDisplayModeNativeFlag`). | `.permanently` |
| `hiDPI` | The best HiDPI mode from `ModeSelection` (exact 2:1 when offered, else the largest HiDPI size below native, e.g. 1904×1071 on a 1080p panel with an override). | `.permanently` |
| `virtualDisplay` | `VirtualDisplayService` creates a `CGVirtualDisplay` (private API, `hiDPI = 1`, 2× native pixels, same refresh rate with a 60 Hz fallback), waits for it to come online, selects its 2x mode only if needed and mirrors the panel onto it with `CGConfigureDisplayMirrorOfDisplay`. | `.forSession`; the display vanishes with the process |
| Override | `HiDPIOverrideProfile` generates the one-key-hidpi byte layout (8-byte 1x entries, 16-byte 2x entries with `0x00000009 0x00200000`), `HiDPIOverrideInstaller` stages it in a 0700 temp dir and `PrivilegedRunner` copies it as root; the file is read back and compared byte-for-byte. | Until the file is removed; takes effect on reconnect |

`DisplaySnapshot.hasUsableHiDPI` uses the panel's physical size (≥ 60 points per inch) so Apple's stock 960×540@2x on a
1080p panel does not count as HiDPI.

## Threading model

| Component | Isolation | Notes |
|---|---|---|
| View models, use cases, stores, display services | `@MainActor` | `CGDisplayMode` and the private classes are not `Sendable`; they never leave the main actor. Domain only sees `DisplayMode` values. |
| `DisplayReconfigurationObserver` | C callback (top-level function, `Unmanaged` user info) | Only yields into an `AsyncStream`; the view model debounces and ignores events during its own transactions. |
| `PrivilegedRunner` | `Task.detached` | The authentication dialog blocks; only a `Sendable` outcome crosses back. |
| `SleepWakeObserver` | `@MainActor`, selector-based | `deinit` only unregisters `self`. |

## Verification (manual, Infrastructure)

1. `make modes` before and after each toggle. On the XB273 GX the current mode goes from
   `1920x1080 px=1920x1080 @120Hz flags=0x2000003` to `1904x1071 px=3808x2142 @120Hz` and back.
2. `system_profiler SPDisplaysDataType` shows "UI Looks like: 1904 x 1071" with HiDPI on, and "Mirror: On" with the
   virtual display on; "Mirror: Off" after turning it off or quitting.
3. Quit the app with HiDPI on: the mode stays. Relaunch: the state is read from the display, not from preferences.
4. Unplug/replug and sleep/wake: the stored configuration (or the profile marked "apply on connect") returns.
5. Override: `scripts/verify-override.sh <vendorHex> <productHex>` (82 entries of 8 bytes and 41 of 16 bytes for a
   1080p panel, `root:wheel 644`).
6. Memory: toggle HiDPI and the virtual display 10× each, open/close the window 10×, then `leaks <pid>` → 0.
