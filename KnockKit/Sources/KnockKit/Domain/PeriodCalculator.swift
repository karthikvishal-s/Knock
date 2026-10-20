import Foundation

/// A half-open date range `[start, end)`.
public struct Period: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case week
        case cycle
        case year
        case custom
    }

    public let kind: Kind
    public let start: Date
    public let end: Date

    public init(kind: Kind, start: Date, end: Date) {
        self.kind = kind
        self.start = start
        self.end = end
    }

    public func contains(_ date: Date) -> Bool { date >= start && date < end }
}

/// All period math lives here: budget cycles with a custom start day, weeks with a custom
/// first weekday, years, and day keys. Built from calendar components only (never by adding
/// seconds), so DST and month lengths are handled by `Calendar`.
public struct PeriodCalculator: Sendable {
    public let calendar: Calendar
    /// 1...31. Months shorter than this start their cycle on their last day.
    public let cycleStartDay: Int

    public init(calendar: Calendar, cycleStartDay: Int = 1) {
        self.calendar = calendar
        self.cycleStartDay = min(max(cycleStartDay, 1), 31)
    }

    // MARK: Periods

    public func period(_ kind: Period.Kind, containing date: Date) -> Period {
        switch kind {
        case .week: week(containing: date)
        case .cycle: cycle(containing: date)
        case .year: year(containing: date)
        case .custom: day(containing: date)
        }
    }

    public func cycle(containing date: Date) -> Period {
        let thisMonth = monthStart(of: date)
        var start = cycleStart(inMonthStarting: thisMonth)
        if date < start {
            start = cycleStart(inMonthStarting: addMonths(-1, to: thisMonth))
        }
        let end = cycleStart(inMonthStarting: addMonths(1, to: monthStart(of: start)))
        return Period(kind: .cycle, start: start, end: end)
    }

    public func week(containing date: Date) -> Period {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let start = addDays(-offset, to: startOfDay)
        return Period(kind: .week, start: start, end: addDays(7, to: start))
    }

    public func year(containing date: Date) -> Period {
        let year = calendar.component(.year, from: date)
        let start = makeDate(year: year, month: 1, day: 1)
        return Period(kind: .year, start: start, end: makeDate(year: year + 1, month: 1, day: 1))
    }

    public func day(containing date: Date) -> Period {
        let start = calendar.startOfDay(for: date)
        return Period(kind: .custom, start: start, end: addDays(1, to: start))
    }

    /// A custom range covering whole days from `first` through `last` inclusive.
    public func custom(from first: Date, through last: Date) -> Period {
        let (a, b) = first <= last ? (first, last) : (last, first)
        let start = calendar.startOfDay(for: a)
        return Period(kind: .custom, start: start, end: addDays(1, to: calendar.startOfDay(for: b)))
    }

    /// The period `count` steps before (negative) or after (positive) `period`.
    public func shifted(_ period: Period, by count: Int) -> Period {
        guard count != 0 else { return period }
        switch period.kind {
        case .week:
            return week(containing: addDays(7 * count, to: period.start))
        case .cycle:
            let month = addMonths(count, to: monthStart(of: period.start))
            let start = cycleStart(inMonthStarting: month)
            return Period(kind: .cycle, start: start, end: cycleStart(inMonthStarting: addMonths(1, to: month)))
        case .year:
            return year(containing: addMonths(12 * count, to: period.start))
        case .custom:
            let length = dayCount(in: period)
            let start = addDays(length * count, to: period.start)
            return Period(kind: .custom, start: start, end: addDays(length, to: start))
        }
    }

    // MARK: Days

    public func dayCount(in period: Period) -> Int {
        calendar.dateComponents([.day], from: period.start, to: period.end).day ?? 0
    }

    public func days(in period: Period) -> [Date] {
        (0..<dayCount(in: period)).map { addDays($0, to: period.start) }
    }

    /// Days from the period start through the day containing `now`, inclusive.
    /// The whole period if it's in the past; 0 if it hasn't started.
    public func daysElapsed(in period: Period, now: Date) -> Int {
        if now < period.start { return 0 }
        if now >= period.end { return dayCount(in: period) }
        return (calendar.dateComponents([.day], from: period.start, to: calendar.startOfDay(for: now)).day ?? 0) + 1
    }

    /// Days left in the period including today.
    public func daysRemaining(in period: Period, now: Date) -> Int {
        if now >= period.end { return 0 }
        if now < period.start { return dayCount(in: period) }
        return dayCount(in: period) - daysElapsed(in: period, now: now) + 1
    }

    /// `yyyyMMdd` for the day containing `date`.
    public func dayKey(for date: Date) -> Int32 {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return Int32((c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0))
    }

    public func startOfDay(forDayKey key: Int32) -> Date? {
        let value = Int(key)
        let year = value / 10_000, month = value / 100 % 100, day = value % 100
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components), calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    // MARK: Helpers

    private func cycleStart(inMonthStarting month: Date) -> Date {
        let length = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
        let c = calendar.dateComponents([.year, .month], from: month)
        return makeDate(year: c.year ?? 2000, month: c.month ?? 1, day: min(cycleStartDay, length))
    }

    private func monthStart(of date: Date) -> Date {
        let c = calendar.dateComponents([.year, .month], from: date)
        return makeDate(year: c.year ?? 2000, month: c.month ?? 1, day: 1)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    private func addMonths(_ months: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: months, to: date) ?? date
    }

    private func addDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }
}
