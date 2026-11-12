# Security Policy

## Supported versions

Only the latest code on the `main` branch receives security fixes.

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Use GitHub's private vulnerability reporting on this repository ("Security" tab → "Report a vulnerability"). You
will receive an acknowledgement within 7 days and a fix or mitigation plan within 30 days for confirmed issues.

## Scope and design guarantees

LiteDisplay changes system display configuration and, on request, writes one file as root. It is designed so that
the following always hold. A violation of any of them is considered a security bug:

- The app never opens network connections, never sends telemetry and never loads code dynamically.
- Administrator rights are requested only through the standard macOS password prompt, only in direct response to a
  user click, never at launch. There is no `sudo`, no setuid binary and no persistent privileged helper.
- Exactly one file, `LiteDisplay/Infrastructure/Override/PrivilegedRunner.swift`, spawns a process. The privileged
  command is built from constants and shell-quoted paths; display vendor and product ids are validated as
  hexadecimal before use.
- The only location written as root is the display override for the selected monitor under
  `/Library/Displays/Contents/Resources/Overrides/`. The file is staged in a private temporary directory
  (`0700`/`0600`, deleted afterwards) and read back and compared byte for byte after installation.
- Persisted settings and profiles are written atomically and validated when loaded.
- Display mode changes go through CoreGraphics configuration transactions that are cancelled on every error path.
  Gamma tables are restored when the app quits.
- Logs never contain file paths or display names in plain text (`os.Logger` with `privacy: .private`).
- The binary ships with the hardened runtime enabled.

## Known trade-offs

- The app is **not sandboxed**: changing display configuration and installing a display override are not possible
  from the App Sandbox.
- The app is **ad-hoc signed and not notarized**. Build it from source, or verify the published SHA-256 of a
  release archive.
- The virtual display uses the private `CGVirtualDisplay` API, declared with `weak_import` and guarded at runtime.
  It is confined to `LiteDisplay/Infrastructure/VirtualDisplay`.
