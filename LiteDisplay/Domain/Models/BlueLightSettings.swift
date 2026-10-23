// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import Foundation

/// A wall-clock time without a date.
struct TimeOfDay: Codable, Hashable, Sendable, Comparable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    var minutesSinceMidnight: Int {
        hour * 60 + minute
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    static func of(_ date: Date, calendar: Calendar = .current) -> TimeOfDay {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }
}

/// When the blue light filter is on.
enum BlueLightSchedule: Codable, Hashable, Sendable {
    case always
    /// Daily window; may cross midnight (e.g. 18:00 → 07:00).
    case daily(start: TimeOfDay, end: TimeOfDay)

    static let defaultDaily = BlueLightSchedule.daily(start: TimeOfDay(hour: 18, minute: 0), end: TimeOfDay(hour: 7, minute: 0))

    func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .always:
            return true
        case let .daily(start, end):
            let now = TimeOfDay.of(date, calendar: calendar).minutesSinceMidnight
            let from = start.minutesSinceMidnight
            let until = end.minutesSinceMidnight
            if from == until {
                return true
            }
            return from < until ? (now >= from && now < until) : (now >= from || now < until)
        }
    }
}

/// Which displays the filter touches.
enum BlueLightScope: String, Codable, Sendable, CaseIterable, Identifiable {
    case externalDisplays
    case allDisplays

    var id: String {
        rawValue
    }
}

/// User preferences for the blue light filter.
struct BlueLightSettings: Codable, Hashable, Sendable {
    static let minimumKelvin = 2700
    static let maximumKelvin = 6500
    static let defaultKelvin = 4200

    var isEnabled = false
    /// Colour temperature of the white point; 6500 K is unchanged, lower is warmer.
    var kelvin = BlueLightSettings.defaultKelvin
    var scope = BlueLightScope.externalDisplays
    var schedule = BlueLightSchedule.always

    /// Clamped copy, for values read back from disk.
    var sanitized: BlueLightSettings {
        var copy = self
        copy.kelvin = min(max(kelvin, Self.minimumKelvin), Self.maximumKelvin)
        return copy
    }

    /// True when the filter should be applied right now.
    func shouldApply(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        isEnabled && schedule.isActive(at: date, calendar: calendar)
    }
}
