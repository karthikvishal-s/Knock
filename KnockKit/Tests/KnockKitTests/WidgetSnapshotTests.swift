import Foundation
import SwiftData
import Testing
@testable import KnockKit

@MainActor
struct WidgetSnapshotTests {
    @Test func snapshotMatchesServicesAndRoundTrips() throws {
        let container = try KnockStore.makeInMemoryContainer()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 20)) ?? .now
        try SampleData.populate(context: container.mainContext, months: 2, now: now, calendar: calendar)
        let calc = PeriodCalculator(calendar: calendar)

        let snapshot = try WidgetSnapshotBuilder.build(context: container.mainContext, calculator: calc, currencyCode: "INR", showsAmounts: true, now: now)
        let totals = try TransactionService(context: container.mainContext, calculator: calc).totals(in: calc.cycle(containing: now))
        #expect(snapshot.spentMinor == totals.netSpendMinor)
        #expect(snapshot.incomeMinor == totals.incomeMinor)
        #expect(snapshot.budgetMinor == 6_000_000)
        #expect(snapshot.daysRemaining == 13)
        #expect(snapshot.tomorrowPerDayMinor != nil)
        #expect(snapshot.topCategories.count <= 4)
        #expect(snapshot.topCategories.map(\.spentMinor) == snapshot.topCategories.map(\.spentMinor).sorted(by: >))
        #expect(snapshot.recent.count == 4)

        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try WidgetSnapshotStore.write(snapshot, directory: directory)
        #expect(WidgetSnapshotStore.read(directory: directory) == snapshot)
    }

    @Test func missingFileReadsNil() {
        #expect(WidgetSnapshotStore.read(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)) == nil)
    }
}
