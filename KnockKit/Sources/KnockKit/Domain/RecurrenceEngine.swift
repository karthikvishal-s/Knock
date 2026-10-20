import Foundation

/// When a recurring rule fires. Monthly rules on the 29th–31st land on the month's last day
/// in shorter months; yearly rules on 29 Feb land on 28 Feb in non-leap years.
public struct RecurrenceSpec: Sendable, Equatable {
    public var frequency: RecurrenceFrequency
    /// Every `interval` days / weeks / months / years.
    public var interval: Int
    /// Weekly only: 1 = Sunday … 7 = Saturday. Empty means the start date's weekday.
    public var weekdays: [Int]
    /// Monthly only: 1...31. `nil` means the start date's day.
    public var dayOfMonth: Int?
    public var startDate: Date
    public var endDate: Date?

    public init(frequency: RecurrenceFrequency, interval: Int = 1, weekdays: [Int] = [], dayOfMonth: Int? = nil, startDate: Date, endDate: Date? = nil) {
        self.frequency = frequency
        self.interval = max(interval, 1)
        self.weekdays = weekdays
        self.dayOfMonth = dayOfMonth
        self.startDate = startDate
        self.endDate = endDate
    }
}

public enum RecurrenceEngine {
    /// The first occurrence strictly after `date` (or at/after the start, if `date` is before it).
    public static func next(after date: Date, spec: RecurrenceSpec, calendar: Calendar) -> Date? {
        let candidates = occurrences(of: spec, from: date, limit: 1, calendar: calendar, inclusive: false)
        return candidates.first
    }

    /// Occurrences within `[from, through]`.
    public static func occurrences(of spec: RecurrenceSpec, from: Date, through: Date, calendar: Calendar) -> [Date] {
        occurrences(of: spec, from: from, limit: 2_000, calendar: calendar, inclusive: true).filter { $0 <= through }
    }

    static func occurrences(of spec: RecurrenceSpec, from: Date, limit: Int, calendar: Calendar, inclusive: Bool) -> [Date] {
        var results: [Date] = []
        // Occurrences keep the start's exact time of day (to the second), so the first one
        // equals the start date and comparisons against it are exact.
        let time = calendar.dateComponents([.hour, .minute, .second], from: spec.startDate)
        let start = spec.startDate
        let lowerBound = max(from, start)
        var index = 0
        // Walk occurrence indices from the start; skip ones before the lower bound.
        // Daily/weekly could jump ahead arithmetically, but rule counts are tiny.
        while results.count < limit, index < 50_000 {
            for candidate in candidates(at: index, spec: spec, time: time, calendar: calendar) {
                if let end = spec.endDate, candidate > end { return results }
                let passes = inclusive ? candidate >= lowerBound : (candidate > from && candidate >= start)
                if passes {
                    results.append(candidate)
                    if results.count == limit { return results }
                }
            }
            index += 1
        }
        return results
    }

    /// The occurrence(s) for the `index`-th period since the start.
    private static func candidates(at index: Int, spec: RecurrenceSpec, time: DateComponents, calendar: Calendar) -> [Date] {
        let start = calendar.startOfDay(for: spec.startDate)
        func at(_ day: Date) -> Date {
            calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: time.second ?? 0, of: day) ?? day
        }
        switch spec.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: index * spec.interval, to: start).map { [at($0)] } ?? []
        case .weekly:
            guard let weekStart = calendar.date(byAdding: .day, value: 7 * index * spec.interval, to: start) else { return [] }
            let startWeekday = calendar.component(.weekday, from: start)
            let days = spec.weekdays.isEmpty ? [startWeekday] : spec.weekdays.sorted { (($0 - startWeekday + 7) % 7) < (($1 - startWeekday + 7) % 7) }
            return days.compactMap { weekday in
                calendar.date(byAdding: .day, value: (weekday - startWeekday + 7) % 7, to: weekStart).map(at)
            }
        case .monthly:
            guard let month = calendar.date(byAdding: .month, value: index * spec.interval, to: monthStart(start, calendar)) else { return [] }
            let wanted = spec.dayOfMonth ?? calendar.component(.day, from: start)
            let length = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
            return calendar.date(byAdding: .day, value: min(wanted, length) - 1, to: month).map { [at($0)] } ?? []
        case .yearly:
            let components = calendar.dateComponents([.month, .day], from: start)
            let year = calendar.component(.year, from: start) + index * spec.interval
            guard let month = calendar.date(from: DateComponents(year: year, month: components.month, day: 1)) else { return [] }
            let length = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
            return calendar.date(byAdding: .day, value: min(components.day ?? 1, length) - 1, to: month).map { [at($0)] } ?? []
        }
    }

    private static func monthStart(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
}

public extension RecurringRule {
    var frequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var mode: RecurringMode {
        get { RecurringMode(rawValue: modeRaw) ?? .autoPost }
        set { modeRaw = newValue.rawValue }
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var spec: RecurrenceSpec {
        RecurrenceSpec(frequency: frequency, interval: interval, weekdays: weekdays ?? [], dayOfMonth: dayOfMonth, startDate: startDate, endDate: endDate)
    }

    var displayName: String {
        if !payee.isEmpty { return payee }
        if !note.isEmpty { return note }
        return category?.name ?? String(localized: "Recurring")
    }
}
