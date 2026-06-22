//
//  TimestampFormatter.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Foundation

/// Formats event occurrence times for human-readable terminal output.
public enum TerminalTimestampFormatter {
    /// Returns a local 24-hour timestamp with millisecond precision.
    public static func format(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let style = Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(3))",
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone,
            calendar: calendar
        )

        return "[\(date.formatted(style))]"
    }
}

/// Formats event occurrence times for human-readable reports.
public enum ReportTimestampFormatter {
    /// Returns a local ISO 8601 timestamp with milliseconds and a numeric UTC offset
    /// (e.g. `2025-06-15T15:06:40.123+00:00`). Never uses `Z` — always emits `+HH:MM`.
    public static func format(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        // Round to millisecond precision first so the seconds and milliseconds fields are
        // derived from the same instant (prevents an off-by-one-second when fractional
        // seconds round up to a full second).
        let rounded = Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents(in: timeZone, from: rounded)
        let year = comps.year ?? 0
        let month = comps.month ?? 0
        let day = comps.day ?? 0
        let hour = comps.hour ?? 0
        let min = comps.minute ?? 0
        let sec = comps.second ?? 0
        let ms = Int((Double(comps.nanosecond ?? 0) / 1_000_000).rounded())
        let offset = timeZone.secondsFromGMT(for: rounded)
        let sign = offset >= 0 ? "+" : "-"
        let absOffset = abs(offset)
        let offsetH = absOffset / 3600
        let offsetM = (absOffset % 3600) / 60
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%03d%@%02d:%02d",
            year, month, day, hour, min, sec, ms, sign, offsetH, offsetM
        )
    }
}
