// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Runs one shell command as administrator after the user authenticates. The only privilege boundary of the app.
protocol PrivilegedExecuting: Sendable {
    func run(_ command: String, prompt: String) async throws(LiteDisplayError)
}
