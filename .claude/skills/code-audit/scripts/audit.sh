#!/bin/bash
# LiteDisplay code audit: lint, format, static analysis and project-specific safety scans.
# Read-only. Exit code is non-zero when SwiftLint reports errors, SwiftFormat finds violations,
# or a hard-FAIL scan hits (CGDisplaySetDisplayMode, a transaction file without CGCancelDisplayConfiguration,
# Info.plist / entitlements / project.yml / CGVirtualDisplay.h contract violations).
# Build products stay outside the repository: the analyzer uses -derivedDataPath under $TMPDIR.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$ROOT" || exit 2
export PATH="/opt/homebrew/bin:$PATH"

MODE="all"
QUICK=0
for arg in "$@"; do
  case "$arg" in
    --changed) MODE="changed" ;;
    --quick) QUICK=1 ;;
  esac
done

if [[ "$MODE" == "changed" ]]; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git rev-parse --verify HEAD >/dev/null 2>&1; then
    FILES=$( { git diff --name-only HEAD -- '*.swift'; git ls-files --others --exclude-standard -- '*.swift'; } | sort -u | grep -E '^(LiteDisplay|LiteDisplayTests)/' )
  else
    echo "No commit to diff against; --changed falls back to the whole project."
    MODE="all"
  fi
fi
if [[ "$MODE" == "all" ]]; then
  FILES=$(find LiteDisplay LiteDisplayTests -name '*.swift' | sort)
fi
if [[ -z "${FILES:-}" ]]; then
  echo "No Swift files in scope."; exit 0
fi
APP_FILES=$(echo "$FILES" | grep -E '^LiteDisplay/' || true)
STATUS=0
HARD_FAIL=0

section() { printf '\n== %s ==\n' "$1"; }

section "Scope ($MODE): $(echo "$FILES" | wc -l | tr -d ' ') files"

section "SwiftFormat (lint mode)"
if command -v swiftformat >/dev/null 2>&1; then
  echo "swiftformat $(swiftformat --version 2>/dev/null | head -1)"
  # Paths come first: `--lint` would otherwise swallow the next path as its value.
  # shellcheck disable=SC2086
  swiftformat $FILES --lint 2>&1 | grep -E 'warning:|error:|did not pass' | sed "s|$ROOT/||"
  if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then STATUS=1; fi
else
  echo "swiftformat not installed (brew install swiftformat)"
fi

section "SwiftLint (strict)"
if command -v swiftlint >/dev/null 2>&1; then
  echo "swiftlint $(swiftlint version 2>/dev/null | head -1)"
  # shellcheck disable=SC2086
  if ! swiftlint lint --strict --quiet --config .swiftlint.yml $FILES; then STATUS=1; fi
else
  echo "swiftlint not installed (brew install swiftlint)"
fi

if [[ "$QUICK" -eq 0 ]]; then
  section "Clang static analyzer"
  DERIVED="${TMPDIR:-/tmp/}LiteDisplay-DerivedData"
  if [[ -d LiteDisplay.xcodeproj ]]; then
    xcodebuild -project LiteDisplay.xcodeproj -scheme LiteDisplay -configuration Debug \
      -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" CODE_SIGN_IDENTITY=- \
      -quiet analyze 2>&1 \
      | grep -E 'warning:|error:' | grep -v appintentsmetadataprocessor | sed "s|$ROOT/||" | sort -u || true
  else
    echo "LiteDisplay.xcodeproj missing (run: xcodegen generate); analyzer skipped"
  fi
fi

scan() {
  # scan "<label>" "<perl regex>" [files...]  — Perl so that \b, \s and look-behinds work on macOS.
  # Returns 1 when there are hits. Lines that are comments or already capture self weakly are skipped.
  local label="$1" regex="$2"; shift 2
  [[ $# -eq 0 ]] && return 0
  local hits
  hits=$(perl -ne 'BEGIN { $re = shift } next if /^\s*\/\//; next if /\[(weak|unowned)\s+self[,\]]|\[self[,\]]/; print "$ARGV:$.: $_" if /$re/; close ARGV if eof' "$regex" "$@" 2>/dev/null || true)
  if [[ -n "$hits" ]]; then
    printf '\n-- %s --\n%s\n' "$label" "$hits"
    return 1
  fi
  return 0
}

fail_scan() {
  # fail_scan "<label>" "<perl regex>" [files...] — like scan, but any hit is a hard FAIL.
  local label="$1"; shift
  if ! scan "FAIL $label" "$@"; then HARD_FAIL=$((HARD_FAIL + 1)); fi
}

file_requires() {
  # file_requires "<label>" "<trigger grep -E>" "<required grep -E>" FAIL|WARN [files...]
  # Reports files that contain the trigger but not the requirement.
  local label="$1" trigger="$2" required="$3" level="$4"; shift 4
  local f hits=""
  for f in "$@"; do
    if grep -qE "$trigger" "$f" && ! grep -qE "$required" "$f"; then hits+="$f"$'\n'; fi
  done
  if [[ -n "$hits" ]]; then
    printf '\n-- %s %s --\n%s' "$level" "$label" "$hits"
    [[ "$level" == "FAIL" ]] && HARD_FAIL=$((HARD_FAIL + 1))
  fi
}

section "Pattern scan (FAIL lines are verdicts; everything else is a candidate for manual review)"
INFRA=$(echo "$APP_FILES" | grep -E '^LiteDisplay/Infrastructure/' || true)
DOMAIN=$(echo "$APP_FILES" | grep -E '^LiteDisplay/Domain/' || true)
FEATURES=$(echo "$APP_FILES" | grep -E '^LiteDisplay/(Features|Shared)/' || true)
NON_PRIVILEGED=$(echo "$APP_FILES" | grep -v 'Infrastructure/Override/PrivilegedRunner.swift' || true)
NON_STORAGE=$(echo "$APP_FILES" | grep -v 'Infrastructure/Storage/' | grep -v 'App/AppContainer.swift' || true)
NON_FONT=$(echo "$APP_FILES" | grep -v 'Infrastructure/System/FontSmoothingService.swift' || true)
NON_VIRTUAL=$(echo "$APP_FILES" | grep -v 'Infrastructure/VirtualDisplay/' || true)
NON_DISPLAY_SERVICES=$(echo "$APP_FILES" | grep -v 'Infrastructure/CoreGraphics/' | grep -v 'Infrastructure/VirtualDisplay/' || true)
NON_OVERRIDE_PROFILE=$(echo "$APP_FILES" | grep -v 'Domain/Models/HiDPIOverrideProfile.swift' | grep -v 'Infrastructure/Override/' || true)

# --- Hard failures ---------------------------------------------------------------------------------
# shellcheck disable=SC2086
fail_scan "CGDisplaySetDisplayMode (kCGConfigureForAppOnly: reverts at quit; use a .permanently transaction)" '\bCGDisplaySetDisplayMode\(' $APP_FILES
# shellcheck disable=SC2086
file_requires "CGBeginDisplayConfiguration in a file without CGCancelDisplayConfiguration (error paths leak the transaction)" 'CGBeginDisplayConfiguration' 'CGCancelDisplayConfiguration' FAIL $APP_FILES

# --- Memory / lifetime ---------------------------------------------------------------------------
# shellcheck disable=SC2086
scan "Forced try / cast / unwrap" '(\btry!|\bas!|[A-Za-z0-9_)\]]!\s*[.;,)]|[A-Za-z0-9_)\]]!$)' $APP_FILES
# shellcheck disable=SC2086
scan "Escaping closures that mention self on the same line (check for [weak self])" '(Task\s*(\(|\{)|\.async\s*\{|setEventHandler\s*\{|\.sink\s*\{|addObserver\(forName|onSleep:\s*\{|onWake:\s*\{|displaysDidChange\s*=\s*\{)[^\n]*\bself\b' $APP_FILES
# shellcheck disable=SC2086
scan "onAppear launching a Task (never cancelled; use .task or a stored Task)" '\.onAppear\s*\{[^}]*Task\s*\{' $APP_FILES
# shellcheck disable=SC2086
scan "Timer.scheduledTimer / Timer (retains target or closure)" 'Timer\.scheduledTimer|Timer\(' $APP_FILES
# shellcheck disable=SC2086
scan "unowned captures" '\bunowned\b' $APP_FILES
# shellcheck disable=SC2086
scan "Observers added (verify removeObserver(self) in stop() and deinit, or a stored token)" 'addObserver\(' $APP_FILES
# shellcheck disable=SC2086
file_requires "CGDisplayRegisterReconfigurationCallback in a file without CGDisplayRemoveReconfigurationCallback (dangling pointer on the next display change)" 'CGDisplayRegisterReconfigurationCallback' 'CGDisplayRemoveReconfigurationCallback' WARN $APP_FILES
# shellcheck disable=SC2086
scan "Unmanaged.passRetained (the observer must be passUnretained and removed in deinit)" 'passRetained\(' $APP_FILES
# shellcheck disable=SC2086
scan "CGDisplayCreateUUIDFromDisplayID without takeRetainedValue on the same line (Create rule)" 'CGDisplayCreateUUIDFromDisplayID\((?![^\n]*takeRetainedValue)' $APP_FILES
# shellcheck disable=SC2086
scan "terminationHandler assigned to something other than nil (known crash at exit; retains captures)" 'terminationHandler\s*=(?!\s*nil\b)' $APP_FILES

# --- Concurrency -----------------------------------------------------------------------------------
# shellcheck disable=SC2086
scan "Blocking primitives (use Task.sleep / async APIs)" '(DispatchSemaphore|\.wait\(\)|DispatchGroup\(\)|Thread\.sleep|RunLoop\.(main|current)\.run|(?<![.\w])(usleep|sleep)\()' $APP_FILES
# shellcheck disable=SC2086
[[ -n "$NON_PRIVILEGED" ]] && scan "Blocking subprocess calls outside PrivilegedRunner" '(waitUntilExit|readDataToEndOfFile)' $NON_PRIVILEGED
# shellcheck disable=SC2086
[[ -n "$NON_PRIVILEGED" ]] && scan "Task.detached outside PrivilegedRunner (only the blocking osascript may be detached)" 'Task\.detached' $NON_PRIVILEGED
# shellcheck disable=SC2086
[[ -n "$INFRA" ]] && scan "DispatchQueue.main / MainActor.run in Infrastructure" '(DispatchQueue\.main|MainActor\.run|RunLoop\.main)' $INFRA
# shellcheck disable=SC2086
scan "Concurrency escape hatches (each needs a comment proving the assumption; none expected in the app target)" '(@unchecked Sendable|nonisolated\(unsafe\)|assumeIsolated|assertIsolated|@preconcurrency)' $APP_FILES
# shellcheck disable=SC2086
[[ -n "$DOMAIN" ]] && scan "Domain importing frameworks (Domain is Foundation-only)" '^import (AppKit|SwiftUI|CoreGraphics|IOKit|ServiceManagement|OSLog|Observation|CoreFoundation)' $DOMAIN
# shellcheck disable=SC2086
[[ -n "$NON_DISPLAY_SERVICES" ]] && scan "CGDisplayMode / CGDisplayConfigRef outside Infrastructure/CoreGraphics|VirtualDisplay (not Sendable; only the Shared bridge may mention CGDisplayMode)" '\b(CGDisplayMode\b|CGDisplayConfigRef)' $(echo "$NON_DISPLAY_SERVICES" | grep -v 'Shared/Extensions/CGDisplayMode+DisplayMode.swift' || true)

# --- Security / privilege ---------------------------------------------------------------------------
# shellcheck disable=SC2086
scan "Networking / telemetry" '(URLSession|URLRequest|NWConnection|NWListener|CFSocket|CFStream|import Network|WKWebView|Analytics|Telemetry|Crashlytics|Sentry|MetricKit|MXMetricManager)' $APP_FILES
# shellcheck disable=SC2086
[[ -n "$NON_PRIVILEGED" ]] && scan "Process spawning outside PrivilegedRunner" '((?<![.\w])Process\(|NSTask|posix_spawn|(?<![.\w])system\(|popen\(|execv|osascript|NSAppleScript)' $NON_PRIVILEGED
# shellcheck disable=SC2086
[[ -n "$NON_PRIVILEGED" ]] && scan "'with administrator privileges' outside PrivilegedRunner" 'with administrator privileges' $NON_PRIVILEGED
# shellcheck disable=SC2086
scan "sudo anywhere" '\bsudo\b' $APP_FILES
# shellcheck disable=SC2086
scan "Persistent privilege / helper tools / TCC-gated APIs (none expected)" '(SMJobBless|SMAppService\.(daemon|agent|loginItem)|AuthorizationExecuteWithPrivileges|AuthorizationCreate|NSXPCConnection|LaunchDaemons|tell application|CGRequestScreenCaptureAccess|CGPreflightScreenCaptureAccess|AXIsProcessTrusted|AXUIElement|CGEvent\.tapCreate|SCShareableContent|IOHIDManager|AVCaptureDevice|CLLocationManager)' $APP_FILES
# shellcheck disable=SC2086
scan "Dynamic code loading" '\b(dlopen|dlsym|NSBundle\.load|Bundle\([^)]*\)\.load|performSelector|NSSelectorFromString|objc_getClass)\b' $APP_FILES
# shellcheck disable=SC2086
scan "Destructive or system-wide commands in the privileged command" '(rm -rf|chmod -R|chown -R|killall|kextcache|\breboot\b|launchctl|defaults write|/System/)' $APP_FILES
# shellcheck disable=SC2086
scan "print / NSLog" '^\s*(print|debugPrint|NSLog|dump)\(' $APP_FILES
# shellcheck disable=SC2086
[[ -n "$NON_STORAGE" ]] && scan "UserDefaults outside Storage / AppContainer" 'UserDefaults\.' $NON_STORAGE
# shellcheck disable=SC2086
[[ -n "$NON_FONT" ]] && scan "CFPreferences outside FontSmoothingService" 'CFPreferences(Set|Copy|Synchronize|AppValue)' $NON_FONT
# shellcheck disable=SC2086
scan "CFPreferences AnyUser domain (needs root; affects every account)" 'kCFPreferencesAnyUser' $APP_FILES
# shellcheck disable=SC2086
[[ -n "$NON_OVERRIDE_PROFILE" ]] && scan "/Library path literals outside HiDPIOverrideProfile / Override (only the root command writes there)" '"/Library/|fileURLWithPath: "/Library' $NON_OVERRIDE_PROFILE
# shellcheck disable=SC2086
scan "Shared temp dirs (use FileManager.default.temporaryDirectory with 0700)" '("/tmp|NSTemporaryDirectory\(\)|/var/tmp)' $APP_FILES
# shellcheck disable=SC2086
scan "File writes without .atomic" '\.write\(to:(?![^\n]*\.atomic)' $APP_FILES
# shellcheck disable=SC2086
scan "Logger interpolation of name/path/url/stderr/serial without a privacy annotation" 'Log\.\w+\.(info|debug|error|warning|notice|fault|critical)\(.*\\\([^)]*(?i:url|path|name|stderr|serial|title)\w*(?![^)]*privacy:)[^)]*\)' $APP_FILES

# --- Display API -----------------------------------------------------------------------------------
# shellcheck disable=SC2086
[[ -n "$NON_VIRTUAL" ]] && scan "CGVirtualDisplay outside Infrastructure/VirtualDisplay" '\bCGVirtualDisplay' $NON_VIRTUAL
# shellcheck disable=SC2086
[[ -n "$NON_DISPLAY_SERVICES" ]] && scan "Display configuration transactions outside Infrastructure/CoreGraphics|VirtualDisplay" '\b(CGBeginDisplayConfiguration|CGCompleteDisplayConfiguration|CGConfigureDisplayWithDisplayMode|CGConfigureDisplayMirrorOfDisplay)\b' $NON_DISPLAY_SERVICES
# shellcheck disable=SC2086
file_requires "CGDisplayCopyAllDisplayModes in a file without kCGDisplayShowDuplicateLowResolutionModes (HiDPI modes hidden)" 'CGDisplayCopyAllDisplayModes' 'kCGDisplayShowDuplicateLowResolutionModes' WARN $APP_FILES
# shellcheck disable=SC2086
scan "Display APIs the app must never call (layout, capture, fade, restore-all)" '\b(CGDisplayCapture|CGDisplayRelease|CGDisplayFade|CGAcquireDisplayFadeReservation|CGRestorePermanentDisplayConfiguration|CGConfigureDisplayStereoOperation)\b' $APP_FILES
[[ -n "$NON_VIRTUAL" ]] && scan "CGConfigureDisplayOrigin outside VirtualDisplayService (only the mirror source and the unmirrored panel may take the origin)" '\bCGConfigureDisplayOrigin\b' $NON_VIRTUAL
NON_GAMMA=$(echo "$APP_FILES" | grep -v "Infrastructure/System/DisplayGammaService.swift" || true)
[[ -n "$NON_GAMMA" ]] && scan "Gamma table calls outside DisplayGammaService (calibration must be cached once and restored at exit)" '\b(CGSetDisplayTransferBy|CGGetDisplayTransferByTable|CGDisplayRestoreColorSyncSettings)' $NON_GAMMA
# shellcheck disable=SC2086
scan "Physical mode committed .forSession / .forAppOnly (must be .permanently; only virtual mirrors are .forSession)" 'CGCompleteDisplayConfiguration\([^)]*\.(forAppOnly)\)' $APP_FILES
# shellcheck disable=SC2086
scan "Mode ids persisted (ioDisplayModeID changes per connection; persist DisplaySize + rate)" '(ioDisplayModeID|modeID)\s*:\s*Int32' $DOMAIN

# --- Localization ----------------------------------------------------------------------------------
# shellcheck disable=SC2086
[[ -n "$FEATURES" ]] && scan "English-looking UI literals (candidates only; UI strings are pt-BR keys with English in Localizable.xcstrings)" '\b(Text|Button|Toggle|Label|ProgressView|Section|Menu|Picker|TextField|navigationTitle|accessibilityLabel)\("[^"]*(\s(the|and|with|for|your)\s|\b(Enable|Disable|Settings|Display|Open|Save|Delete|Apply|Cancel|Profile|Refresh|Install|Quit|Close|Window|Show|Error|Failed|Virtual|Sharp)\b)' $FEATURES

section "Info.plist / entitlements / project.yml / private header"
PLIST="LiteDisplay/Resources/Info.plist"
ENT="LiteDisplay/Resources/LiteDisplay.entitlements"
PROJECT_YML="project.yml"
HEADER="LiteDisplay/Infrastructure/VirtualDisplay/CGVirtualDisplay.h"
CATALOG="LiteDisplay/Resources/Localizable.xcstrings"

fail() { echo "FAIL $1"; HARD_FAIL=$((HARD_FAIL + 1)); }
ok() { echo "ok   $1"; }

if [[ -f "$ENT" ]]; then
  if grep -A1 'com.apple.security.app-sandbox' "$ENT" | grep -q '<false/>'; then ok "App Sandbox disabled (direct distribution)"; else fail "com.apple.security.app-sandbox must be present and <false/> in $ENT"; fi
  if grep -qE 'com\.apple\.security\.network' "$ENT"; then fail "network entitlement present in $ENT"; else ok "no network entitlements"; fi
  if grep -qE 'com\.apple\.security\.(device\.camera|device\.audio-input|personal-information\.location)' "$ENT"; then fail "camera/microphone/location entitlement present in $ENT"; else ok "no camera/microphone/location entitlements"; fi
  if grep -qE 'cs\.(allow-jit|disable-library-validation|allow-dyld-environment-variables|allow-unsigned-executable-memory)' "$ENT"; then fail "hardened-runtime exception entitlement present in $ENT"; else ok "no hardened-runtime exceptions"; fi
  ENT_KEYS=$(grep -c '<key>' "$ENT" | tr -d ' ')
  if [[ "$ENT_KEYS" -eq 1 ]]; then ok "entitlements contain exactly one key"; else echo "WARN $ENT has $ENT_KEYS keys (expected 1: app-sandbox)"; fi
else
  fail "$ENT missing"
fi

if [[ -f "$PLIST" ]]; then
  if grep -A1 '<key>LSUIElement</key>' "$PLIST" | grep -q '<true/>'; then ok "LSUIElement true (menu-bar app)"; else fail "LSUIElement must be <true/> in $PLIST"; fi
  if grep -qE 'NS(Camera|Microphone|Location\w*|AppleEvents|Contacts|Calendars|Photos|Bluetooth\w*)UsageDescription' "$PLIST"; then fail "usage-description key present in $PLIST (no TCC-gated capability is used)"; else ok "no usage-description keys"; fi
  if grep -A1 '<key>NSSupportsSuddenTermination</key>' "$PLIST" | grep -q '<false/>'; then ok "NSSupportsSuddenTermination false (unmirror before exit)"; else echo "WARN NSSupportsSuddenTermination should be <false/> so applicationShouldTerminate can unmirror"; fi
else
  fail "$PLIST missing"
fi

if [[ -f "$PROJECT_YML" ]]; then
  if grep -qE '^\s*ENABLE_HARDENED_RUNTIME:\s*YES' "$PROJECT_YML"; then ok "ENABLE_HARDENED_RUNTIME: YES"; else fail "ENABLE_HARDENED_RUNTIME: YES missing from $PROJECT_YML"; fi
  if grep -qE '^\s*ENABLE_APP_SANDBOX:\s*NO' "$PROJECT_YML"; then ok "ENABLE_APP_SANDBOX: NO"; else echo "WARN ENABLE_APP_SANDBOX: NO not found in $PROJECT_YML"; fi
  if grep -qE '^\s*SWIFT_STRICT_CONCURRENCY:\s*complete' "$PROJECT_YML"; then ok "SWIFT_STRICT_CONCURRENCY: complete"; else echo "WARN SWIFT_STRICT_CONCURRENCY: complete not found in $PROJECT_YML"; fi
  if grep -qE '^\s*packages:|XCRemoteSwiftPackageReference' "$PROJECT_YML"; then fail "Swift package dependency declared in $PROJECT_YML (zero third-party dependencies)"; else ok "no package dependencies"; fi
  if grep -qE 'INFOPLIST_KEY_\w+UsageDescription' "$PROJECT_YML"; then fail "INFOPLIST_KEY_*UsageDescription in $PROJECT_YML"; fi
else
  fail "$PROJECT_YML missing"
fi

if [[ -f "$HEADER" ]]; then
  WEAK=$(grep -c 'weak_import' "$HEADER" | tr -d ' ')
  if [[ "$WEAK" -ge 1 ]]; then ok "CGVirtualDisplay.h uses weak_import ($WEAK declarations)"; else fail "$HEADER has no weak_import (the app would fail to launch on a macOS without the private classes)"; fi
  IFACES=$(grep -c '^@interface' "$HEADER" | tr -d ' ')
  if [[ "$WEAK" -lt "$IFACES" ]]; then echo "WARN $IFACES @interface declarations but only $WEAK weak_import attributes in $HEADER"; fi
else
  fail "$HEADER missing"
fi

if [[ -f "$CATALOG" ]]; then
  ENTRIES=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d.get("strings", {})))' "$CATALOG" 2>/dev/null || echo 0)
  UNTRANSLATED=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sum(1 for k,v in d.get("strings", {}).items() if k and "en" not in v.get("localizations", {})))' "$CATALOG" 2>/dev/null || echo 0)
  if [[ "$ENTRIES" -eq 0 ]]; then echo "NOTE $CATALOG has no entries yet (extract keys from the build's .stringsdata and add English translations)"
  elif [[ "$UNTRANSLATED" -gt 0 ]]; then echo "WARN Localizable.xcstrings has $UNTRANSLATED of $ENTRIES strings without an English translation"
  else ok "Localizable.xcstrings has $ENTRIES strings, all translated to English"; fi
else
  echo "WARN $CATALOG missing"
fi

STRAY=$(find . -maxdepth 2 \( -name DerivedData -o -name build -o -name '*.app' -o -name '*.xcarchive' \) -not -path './.git/*' 2>/dev/null)
if [[ -n "$STRAY" ]]; then echo "WARN build products inside the checkout (keep them under \$TMPDIR):"; echo "$STRAY"; else ok "no build products inside the checkout"; fi

section "Result"
if [[ "$HARD_FAIL" -gt 0 ]]; then
  echo "FAIL: $HARD_FAIL hard failure(s) above."
elif [[ "$STATUS" -ne 0 ]]; then
  echo "Tooling reported errors (see above)."
else
  echo "Tooling passed. Review the candidates above manually."
fi
if [[ "$HARD_FAIL" -gt 0 || "$STATUS" -ne 0 ]]; then exit 1; fi
exit 0
