import Foundation
import Testing
@testable import KnockKit

struct PeriodCalculatorTests {
    static func calendar(_ timeZone: String, firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .gmt
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h)) ?? .distantPast
    }

    /// (year, month, day) of a date in the calendar's time zone.
    static func ymd(_ date: Date, _ calendar: Calendar) -> [Int] {
        let c = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return [c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? -1]
    }

    // MARK: Cycles

    @Test func calendarMonthCycle() {
        let cal = Self.calendar("Asia/Kolkata")
        let calc = PeriodCalculator(calendar: cal, cycleStartDay: 1)
        let period = calc.cycle(containing: Self.date(2026, 10, 19, in: cal))
        #expect(Self.ymd(period.start, cal) == [2026, 10, 1, 0])
        #expect(Self.ymd(period.end, cal) == [2026, 11, 1, 0])
        #expect(calc.dayCount(in: period) == 31)
    }

    @Test func salaryDayCycleBeforeAndAfterStart() {
        let cal = Self.calendar("Asia/Kolkata")
        let calc = PeriodCalculator(calendar: cal, cycleStartDay: 15)
        let before = calc.cycle(containing: Self.date(2026, 10, 14, in: cal))
        #expect(Self.ymd(before.start, cal) == [2026, 9, 15, 0])
        #expect(Self.ymd(before.end, cal) == [2026, 10, 15, 0])
        let onDay = calc.cycle(containing: Self.date(2026, 10, 15, 0, in: cal))
        #expect(Self.ymd(onDay.start, cal) == [2026, 10, 15, 0])
    }

    @Test(arguments: [
        // (startDay, year, month, day) → expected start (month, day)
        (31, 2026, 2, 27, 1, 31),
        (31, 2026, 2, 28, 2, 28),
        (31, 2028, 2, 28, 1, 31),
        (31, 2028, 2, 29, 2, 29),
        (30, 2026, 3, 29, 2, 28),
        (31, 2026, 4, 30, 4, 30),
        (29, 2026, 3, 1, 2, 28),
    ])
    func shortMonthsClampStartDay(startDay: Int, y: Int, m: Int, d: Int, expectedMonth: Int, expectedDay: Int) {
        let cal = Self.calendar("Asia/Kolkata")
        let calc = PeriodCalculator(calendar: cal, cycleStartDay: startDay)
        let period = calc.cycle(containing: Self.date(y, m, d, in: cal))
        let start = Self.ymd(period.start, cal)
        #expect(start[1] == expectedMonth && start[2] == expectedDay)
        #expect(period.contains(Self.date(y, m, d, in: cal)))
    }

    @Test func cyclesTileWithoutGapsAcrossAYear() {
        let cal = Self.calendar("America/New_York")
        let calc = PeriodCalculator(calendar: cal, cycleStartDay: 31)
        var period = calc.cycle(containing: Self.date(2026, 1, 10, in: cal))
        for _ in 0..<24 {
            let next = calc.shifted(period, by: 1)
            #expect(next.start == period.end)
            #expect(calc.shifted(next, by: -1) == period)
            period = next
        }
    }

    @Test func yearBoundary() {
        let cal = Self.calendar("Asia/Kolkata")
        let calc = PeriodCalculator(calendar: cal, cycleStartDay: 25)
        let period = calc.cycle(containing: Self.date(2027, 1, 3, in: cal))
        #expect(Self.ymd(period.start, cal) == [2026, 12, 25, 0])
        #expect(Self.ymd(period.end, cal) == [2027, 1, 25, 0])
    }

    // MARK: DST

    @Test(arguments: ["America/New_York", "Europe/London"])
    func dstMonthsStartAtLocalMidnight(zone: String) {
        let cal = Self.calendar(zone)
        let calc = PeriodCalculator(calendar: cal)
        for month in [3, 10, 11] {
            let period = calc.cycle(containing: Self.date(2026, month, 15, in: cal))
            #expect(Self.ymd(period.start, cal)[3] == 0)
            #expect(Self.ymd(period.end, cal)[3] == 0)
        }
        let march = calc.cycle(containing: Self.date(2026, 3, 15, in: cal))
        #expect(calc.dayCount(in: march) == 31)
        #expect(calc.days(in: march).count == 31)
        #expect(calc.days(in: march).allSatisfy { Self.ymd($0, cal)[3] == 0 })
    }

    @Test func dstWeekHasSevenDays() {
        let cal = Self.calendar("America/New_York", firstWeekday: 1)
        let calc = PeriodCalculator(calendar: cal)
        // US DST starts Sunday 2026-03-08.
        let week = calc.week(containing: Self.date(2026, 3, 10, in: cal))
        #expect(Self.ymd(week.start, cal) == [2026, 3, 8, 0])
        #expect(calc.dayCount(in: week) == 7)
    }

    // MARK: Weeks & years

    @Test(arguments: [(1, 18), (2, 19)])
    func weekRespectsFirstWeekday(firstWeekday: Int, expectedStartDay: Int) {
        let cal = Self.calendar("Asia/Kolkata", firstWeekday: firstWeekday)
        let calc = PeriodCalculator(calendar: cal)
        // 2026-10-21 is a Wednesday.
        let week = calc.week(containing: Self.date(2026, 10, 21, in: cal))
        #expect(Self.ymd(week.start, cal) == [2026, 10, expectedStartDay, 0])
    }

    @Test func yearAndShift() {
        let cal = Self.calendar("Asia/Kolkata")
        let calc = PeriodCalculator(calendar: cal)
        let year = calc.year(containing: Self.date(2028, 7, 1, in: cal))
        #expect(calc.dayCount(in: year) == 366)
        #expect(Self.ymd(calc.shifted(year, by: -2).start, cal) == [2026, 1, 1, 0])
    }

    @Test func customRangeIsInclusiveAndShiftsByLength() {
        let cal = Self.calendar("Asia/Kolkata")
        let calc = PeriodCalculator(calendar: cal)
        let range = calc.custom(from: Self.date(2026, 10, 10, in: cal), through: Self.date(2026, 10, 1, in: cal))
        #expect(calc.dayCount(in: range) == 10)
        #expect(Self.ymd(calc.shifted(range, by: 1).start, cal) == [2026, 10, 11, 0])
    }

    // MARK: Elapsed / remaining

    @Test func elapsedAndRemaining() {
        let cal = Self.calendar("Asia/Kolkata")
        let calc = PeriodCalculator(calendar: cal)
        let october = calc.cycle(containing: Self.date(2026, 10, 1, in: cal))
        let now = Self.date(2026, 10, 19, 21, in: cal)
        #expect(calc.daysElapsed(in: october, now: now) == 19)
        #expect(calc.daysRemaining(in: october, now: now) == 13)
        #expect(calc.daysElapsed(in: october, now: Self.date(2026, 12, 1, in: cal)) == 31)
        #expect(calc.daysRemaining(in: october, now: Self.date(2026, 9, 1, in: cal)) == 31)
        #expect(calc.daysElapsed(in: october, now: Self.date(2026, 9, 1, in: cal)) == 0)
    }

    // MARK: Day keys

    @Test func dayKeysRoundTrip() throws {
        let cal = Self.calendar("Asia/Kolkata")
        let calc = PeriodCalculator(calendar: cal)
        let date = Self.date(2026, 2, 3, 23, in: cal)
        #expect(calc.dayKey(for: date) == 20260203)
        let start = try #require(calc.startOfDay(forDayKey: 20260203))
        #expect(Self.ymd(start, cal) == [2026, 2, 3, 0])
        #expect(calc.startOfDay(forDayKey: 20260230) == nil)
        #expect(calc.startOfDay(forDayKey: 20261301) == nil)
    }

    @Test func dayKeyFollowsTimeZone() {
        let instant = Self.date(2026, 10, 19, 22, in: Self.calendar("Asia/Kolkata"))
        #expect(PeriodCalculator(calendar: Self.calendar("Asia/Kolkata")).dayKey(for: instant) == 20261019)
        #expect(PeriodCalculator(calendar: Self.calendar("Asia/Tokyo")).dayKey(for: instant) == 20261020)
    }

    @Test func startDayIsClampedToValidRange() {
        #expect(PeriodCalculator(calendar: .current, cycleStartDay: 0).cycleStartDay == 1)
        #expect(PeriodCalculator(calendar: .current, cycleStartDay: 40).cycleStartDay == 31)
    }
}
