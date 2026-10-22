// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// The app's only privilege boundary: runs one shell command as administrator through `osascript`, which shows
/// the system authentication dialog. Commands are built by the caller from constants and shell-quoted paths.
struct PrivilegedRunner: PrivilegedExecuting {
    private struct Outcome: Sendable {
        let status: Int32
        let stderr: String
    }

    private static let osascript = "/usr/bin/osascript"
    /// AppleScript error number for "User canceled".
    private static let userCancelled = "-128"

    func run(_ command: String, prompt: String) async throws(LiteDisplayError) {
        let script = [
            "do shell script \(Self.appleScriptLiteral(command))",
            "with administrator privileges",
            "with prompt \(Self.appleScriptLiteral(prompt))"
        ].joined(separator: " ")
        Log.override.info("Requesting administrator privileges")
        // The authentication dialog blocks the calling thread, so the process runs off the main actor.
        let outcome = await Task.detached(priority: .userInitiated) { Self.execute(script) }.value
        guard outcome.status == 0 else {
            if outcome.stderr.contains(Self.userCancelled) {
                Log.override.notice("Administrator prompt cancelled")
                throw .privilegeDenied
            }
            Log.override.error("Privileged command failed: \(outcome.stderr, privacy: .private)")
            throw .privilegedCommandFailed(outcome.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Escapes a string as an AppleScript string literal.
    static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Escapes a path for /bin/sh.
    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func execute(_ script: String) -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: osascript)
        process.arguments = ["-e", script]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return Outcome(status: -1, stderr: error.localizedDescription)
        }
        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Outcome(status: process.terminationStatus, stderr: String(bytes: data, encoding: .utf8) ?? "")
    }
}
