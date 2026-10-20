import Foundation
import SwiftData
import Testing
@testable import KnockKit

@MainActor
struct HistoryQueryTests {
    let context: ModelContext
    let calendar: Calendar
    let now: Date
    let container: ModelContainer

    init() throws {
        container = try KnockStore.makeInMemoryContainer()
        context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
        self.calendar = calendar
        now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 20)) ?? .now
        try SampleData.populate(context: context, months: 4, now: now, calendar: calendar)
    }

    private var query: HistoryQuery { HistoryQuery(context: context, calendar: calendar) }

    private func allPages(_ filter: HistoryFilter = HistoryFilter()) throws -> [DaySection] {
        var sections: [DaySection] = []
        var cursor: Date?
        repeat {
            let page = try query.page(before: cursor, filter: filter)
            sections += page.sections
            cursor = page.nextCursor
        } while cursor != nil
        return sections
    }

    @Test func pagesCoverEveryEntryOnceNewestFirst() throws {
        let total = try context.fetchCount(FetchDescriptor<LedgerEntry>())
        let sections = try allPages()
        let entries = sections.flatMap(\.entries)
        #expect(entries.count == total)
        #expect(Set(entries.map(\.id)).count == total)
        #expect(entries.map(\.date) == entries.map(\.date).sorted(by: >))
        #expect(Set(sections.map(\.dayKey)).count == sections.count, "each day appears in exactly one section")
    }

    @Test func dayTotalsMatchEntries() throws {
        for section in try allPages() {
            #expect(section.totals == Totals(entries: section.entries))
            #expect(section.entries.allSatisfy { $0.dayKey == section.dayKey })
        }
    }

    @Test func firstPageStopsAtMonthBoundaryWithCursor() throws {
        let page = try query.page(before: nil, filter: HistoryFilter(), minimumEntries: 1)
        let cursor = try #require(page.nextCursor)
        #expect(calendar.component(.day, from: cursor) == 1)
        #expect(page.sections.allSatisfy { $0.date >= cursor })
    }

    @Test func filtersByKindAndCategory() throws {
        var filter = HistoryFilter()
        filter.kinds = [.income]
        let income = try allPages(filter).flatMap(\.entries)
        #expect(!income.isEmpty)
        #expect(income.allSatisfy { $0.kind == .income })

        let food = try #require(try context.fetch(FetchDescriptor<LedgerCategory>()).first { $0.name == "Food" })
        filter = HistoryFilter()
        filter.categoryIDs = [food.id]
        let foods = try allPages(filter).flatMap(\.entries)
        #expect(!foods.isEmpty)
        #expect(foods.allSatisfy { $0.category?.id == food.id })
    }

    @Test func searchMatchesPayeeNoteAndAmount() throws {
        var filter = HistoryFilter()
        filter.searchText = "netflix"
        let netflix = try allPages(filter).flatMap(\.entries)
        #expect(!netflix.isEmpty)
        #expect(netflix.allSatisfy { $0.payee == "Netflix" })

        filter.searchText = "649"
        #expect(try allPages(filter).flatMap(\.entries).allSatisfy { $0.amountMinor == 64_900 || $0.note.contains("649") || $0.payee.contains("649") })

        filter.searchText = "zzz-nothing"
        #expect(try allPages(filter).isEmpty)
    }

    @Test func dateAndAmountRange() throws {
        var filter = HistoryFilter()
        let calc = PeriodCalculator(calendar: calendar)
        filter.dateRange = calc.cycle(containing: now)
        filter.minAmount = 1_000
        filter.maxAmount = 25_000
        let entries = try allPages(filter).flatMap(\.entries)
        #expect(!entries.isEmpty)
        #expect(entries.allSatisfy { filter.dateRange?.contains($0.date) == true })
        #expect(entries.allSatisfy { (100_000...2_500_000).contains($0.amountMinor) })
        #expect(filter.activeCount == 2)
    }
}

struct SchemaCompatibilityTests {
    /// CloudKit rules (PLAN.md §4): no unique attributes, every relationship optional.
    @Test func schemaIsCloudKitCompatible() {
        for entity in KnockStore.schema.entities {
            for attribute in entity.attributes {
                #expect(!attribute.options.contains(.unique), "\(entity.name).\(attribute.name) must not be unique")
            }
            for relationship in entity.relationships {
                #expect(relationship.isOptional, "\(entity.name).\(relationship.name) must be optional")
            }
        }
    }
}
