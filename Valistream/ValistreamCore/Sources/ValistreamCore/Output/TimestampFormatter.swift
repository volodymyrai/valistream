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
    /// Returns a local ISO 8601 timestamp with milliseconds and a numeric UTC offset.
    public static func format(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let style = Date.ISO8601FormatStyle(
            dateSeparator: .dash,
            dateTimeSeparator: .standard,
            timeSeparator: .colon,
            timeZoneSeparator: .colon,
            includingFractionalSeconds: true,
            timeZone: timeZone
        )

        return date.formatted(style)
    }
}
