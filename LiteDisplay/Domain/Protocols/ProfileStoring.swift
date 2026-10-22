// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// Persistent profiles.
@MainActor
protocol ProfileStoring: AnyObject {
    var profiles: [Profile] { get }
    func upsert(_ profile: Profile) throws(LiteDisplayError)
    func delete(id: UUID) throws(LiteDisplayError)
}
