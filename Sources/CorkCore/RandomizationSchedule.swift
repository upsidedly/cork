import Foundation

public enum RandomizationFrequency: String, Codable, CaseIterable, Sendable {
    case off, minute, hour, day, week, morningEvening = "morning_evening", custom
    public var title: String {
        switch self {
        case .off: "Off"
        case .minute: "Every minute"
        case .hour: "Every hour"
        case .day: "Every day"
        case .week: "Every week"
        case .morningEvening: "Morning & evening"
        case .custom: "Custom interval"
        }
    }
}
public enum ScheduleUnit: String, Codable, CaseIterable, Sendable {
    case minutes, hours, days, weeks
    public var seconds: TimeInterval {
        switch self { case .minutes: 60; case .hours: 3600; case .days: 86400; case .weeks: 604800 }
    }
    public var maximum: Int { Int(31_536_000 / seconds) }
}
public struct RandomizationSchedule: Codable, Equatable, Sendable {
    public var frequency: RandomizationFrequency = .off
    public var every = 1
    public var unit: ScheduleUnit = .hours
    public var hour = 8
    public var minute = 0
    public var weekday = 2
    public var eveningHour = 18
    public var eveningMinute = 0
    public var nextRun: Date?
    public init() {}
    public var enabled: Bool { frequency != .off }
    public func validate() throws {
        guard (1...unit.maximum).contains(every), (0...23).contains(hour), (0...59).contains(minute),
              (1...7).contains(weekday), (0...23).contains(eveningHour), (0...59).contains(eveningMinute),
              nextRun?.timeIntervalSince1970.isFinite ?? true else { throw CorkError("Choose valid times and an interval from one minute to one year.") }
        if frequency == .morningEvening && hour == eveningHour && minute == eveningMinute { throw CorkError("Choose two different times for morning and evening.") }
    }
    public func next(after now: Date, calendar: Calendar = .autoupdatingCurrent) throws -> Date? {
        try validate()
        guard enabled else { return nil }
        switch frequency {
        case .minute: return now.addingTimeInterval(60)
        case .hour: return now.addingTimeInterval(3600)
        case .custom: return now.addingTimeInterval(Double(every) * unit.seconds)
        default:
            func time(_ hour: Int, _ minute: Int, weekday: Int? = nil) -> Date? {
                var parts = DateComponents(); parts.hour = hour; parts.minute = minute; parts.second = 0; parts.weekday = weekday
                return calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime, repeatedTimePolicy: .first)
            }
            let values: [Date?]
            if frequency == .week { values = [time(hour, minute, weekday: weekday)] }
            else if frequency == .morningEvening { values = [time(hour, minute), time(eveningHour, eveningMinute)] }
            else { values = [time(hour, minute)] }
            guard let result = values.compactMap({ $0 }).min() else { throw CorkError("This schedule has no valid upcoming time.") }
            return result
        }
    }
    public func armed(after now: Date, calendar: Calendar = .autoupdatingCurrent) throws -> Self {
        var value = self; value.nextRun = try next(after: now, calendar: calendar); return value
    }
}
