import Foundation

public struct LocalDay: Hashable, Codable, Comparable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String
    public var description: String { rawValue }

    public init?(rawValue: String) {
        guard rawValue.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { return nil }
        let components = rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3, components[0].count == 4,
              components[1].count == 2, components[2].count == 2,
              let year = Int(components[0]), let month = Int(components[1]),
              let day = Int(components[2]), year >= 1, year <= 9999,
              month >= 1, month <= 12, day >= 1, day <= 31 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        self.rawValue = rawValue
    }

    public init(_ date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        rawValue = String(format: "%04d-%02d-%02d", values.year!, values.month!, values.day!)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public func date(timeZone: TimeZone = .current, minute: Int = 12 * 60) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let values = rawValue.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(
            year: values[0], month: values[1], day: values[2],
            hour: minute / 60, minute: minute % 60
        ))!
    }

    public func adding(days: Int) -> Self {
        let zone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return Self(calendar.date(byAdding: .day, value: days, to: date(timeZone: zone))!, timeZone: zone)
    }

    public var weekday: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.component(.weekday, from: date(timeZone: calendar.timeZone))
    }

    public static func today(timeZone: TimeZone = .current) -> Self { Self(Date(), timeZone: timeZone) }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = Self(rawValue: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid YYYY-MM-DD")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
