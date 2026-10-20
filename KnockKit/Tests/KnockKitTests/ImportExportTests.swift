import Foundation
import SwiftData
import Testing
@testable import KnockKit

struct CSVCodecTests {
    @Test func parsesQuotesNewlinesAndBOM() {
        let text = "\u{FEFF}Date,Note,Amount\r\n2026-10-01,\"Lunch, with \"\"Ravi\"\"\",250\r\n2026-10-02,\"two\nlines\",99\n"
        let rows = CSVCodec.parse(text)
        #expect(rows.count == 3)
        #expect(rows[0] == ["Date", "Note", "Amount"])
        #expect(rows[1] == ["2026-10-01", "Lunch, with \"Ravi\"", "250"])
        #expect(rows[2] == ["2026-10-02", "two\nlines", "99"])
    }

    @Test func detectsSemicolonAndTab() {
        #expect(CSVCodec.parse("a;b;c\n1;2;3")[1] == ["1", "2", "3"])
        #expect(CSVCodec.parse("a\tb\n1\t2")[1] == ["1", "2"])
    }

    @Test func encodeRoundTrips() {
        let rows = [["a", "b,c", "d\"e"], ["line\nbreak", "", "x"]]
        #expect(CSVCodec.parse(CSVCodec.encode(rows)) == rows)
    }
}

struct CSVImporterTests {
    @Test(arguments: [
        ("₹1,23,456.78", "123456.78"), ("-250", "-250"), ("(250.00)", "-250"), ("250 Dr", "-250"), ("1.234,56", "1234.56"),
        ("12,50", "12.5"), ("1,000", "1000"), ("  99.9 ", "99.9"),
    ])
    func parsesAmounts(raw: String, expected: String) {
        #expect(CSVImporter.parseAmount(raw) == Decimal(string: expected))
    }

    @Test func amountRejectsGarbage() {
        #expect(CSVImporter.parseAmount("") == nil)
        #expect(CSVImporter.parseAmount("abc") == nil)
    }

    @Test func detectsDateFormats() {
        #expect(CSVImporter.detectDateFormat(["2026-10-01", "2026-10-15"]) == "yyyy-MM-dd")
        #expect(CSVImporter.detectDateFormat(["01/10/2026", "25/10/2026"]) == "dd/MM/yyyy")
        #expect(CSVImporter.detectDateFormat(["10/25/2026"]) == "MM/dd/yyyy")
        #expect(CSVImporter.detectDateFormat(["2026-10-01 09:30"]) == "yyyy-MM-dd HH:mm")
        #expect(CSVImporter.detectDateFormat(["5 Oct 2026"]) == "d MMM yyyy")
    }

    @Test func guessesBankStatementColumns() {
        let mapping = CSVImporter.guessMapping(header: ["Txn Date", "Narration", "Withdrawal Amt.", "Deposit Amt.", "Closing Balance"])
        #expect(mapping.date == 0)
        #expect(mapping.payee == 1)
        #expect(mapping.debit == 2)
        #expect(mapping.credit == 3)
        #expect(mapping.amount == nil)
        #expect(mapping.isUsable)
    }

    @Test func rowsResolveKindsFromTypeOrSign() {
        let table = [
            ["Date", "Type", "Amount", "Category", "Payee"],
            ["2026-10-01", "Expense", "250", "Food", "Swiggy"],
            ["2026-10-02", "Income", "50000", "Salary", ""],
            ["2026-10-03", "Expense", "-120", "Shopping", "Amazon"],
            ["2026-10-04", "", "300", "Food", ""],
            ["bad date", "Expense", "10", "", ""],
            ["2026-10-05", "Expense", "", "", ""],
        ]
        var mapping = CSVImporter.guessMapping(header: table[0])
        mapping.hasHeader = true
        let rows = CSVImporter.rows(from: table, mapping: mapping, defaultCurrency: "INR")
        #expect(rows.map(\.kind) == [.expense, .income, .refund, .expense, .expense, .expense])
        #expect(rows[2].amount == 120)
        #expect(rows[4].error != nil)
        #expect(rows[5].error != nil)
        #expect(rows[0].line == 2)
    }

    @Test func debitCreditColumns() {
        let table = [["Date", "Description", "Debit", "Credit"], ["01/10/2026", "ATM", "2,000.00", ""], ["02/10/2026", "Salary", "", "85,000.00"]]
        let rows = CSVImporter.rows(from: table, mapping: CSVImporter.guessMapping(header: table[0]), defaultCurrency: "INR")
        #expect(rows.map(\.kind) == [.expense, .income])
        #expect(rows.map(\.amount) == [2_000, 85_000])
        #expect(rows.allSatisfy { $0.error == nil })
    }
}

@MainActor
struct ImportCommitAndBackupTests {
    let calc: PeriodCalculator = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
        return PeriodCalculator(calendar: calendar)
    }()

    @Test func commitCreatesCategoriesAndSkipsDuplicates() throws {
        let container = try KnockStore.makeInMemoryContainer()
        let context = container.mainContext
        try Seeder.seedIfNeeded(context: context)
        let table = [
            ["Date", "Type", "Amount", "Category", "Account", "Payee", "Tags"],
            ["2026-10-01", "expense", "250", "food", "Cash", "Swiggy", "work; lunch"],
            ["2026-10-02", "expense", "99", "Pets", "HDFC Card", "", ""],
        ]
        let rows = CSVImporter.rows(from: table, mapping: CSVImporter.guessMapping(header: table[0]), defaultCurrency: "INR", timeZone: calc.calendar.timeZone)
        let first = try CSVImporter.commit(rows, context: context, calculator: calc)
        #expect(first == ImportResult(imported: 2, skippedDuplicates: 0, failed: 0, createdCategories: 1, createdAccounts: 1))
        let again = try CSVImporter.commit(rows, context: context, calculator: calc)
        #expect(again.imported == 0)
        #expect(again.skippedDuplicates == 2)
        let swiggy = try #require(try context.fetch(FetchDescriptor<LedgerEntry>()).first { $0.payee == "Swiggy" })
        #expect(swiggy.category?.name == "Food", "matches existing category case-insensitively")
        #expect(Set((swiggy.tags ?? []).map(\.name)) == ["work", "lunch"])
        #expect(swiggy.source == .importFile)
    }

    @Test func exportThenImportReproducesTotals() throws {
        let source = try KnockStore.makeInMemoryContainer()
        let now = calc.calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 20)) ?? .now
        try SampleData.populate(context: source.mainContext, months: 2, now: now, calendar: calc.calendar)
        let csv = try CSVExporter.export(context: source.mainContext)

        let target = try KnockStore.makeInMemoryContainer()
        try Seeder.seedIfNeeded(context: target.mainContext)
        let table = CSVCodec.parse(csv)
        let rows = CSVImporter.rows(from: table, mapping: CSVImporter.guessMapping(header: table[0]), defaultCurrency: "INR", timeZone: calc.calendar.timeZone)
        let result = try CSVImporter.commit(rows, context: target.mainContext, calculator: calc)

        let original = try source.mainContext.fetch(FetchDescriptor<LedgerEntry>())
        let imported = try target.mainContext.fetch(FetchDescriptor<LedgerEntry>())
        #expect(result.failed == 0)
        #expect(result.imported + result.skippedDuplicates == original.count)
        let period = Period(kind: .custom, start: .distantPast, end: .distantFuture)
        #expect(Totals(entries: imported).incomeMinor == Totals(entries: original).incomeMinor)
        _ = period
    }

    @Test func backupEraseRestoreIsLossless() throws {
        let container = try KnockStore.makeInMemoryContainer()
        let context = container.mainContext
        let now = calc.calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 20)) ?? .now
        try SampleData.populate(context: context, months: 2, now: now, calendar: calc.calendar)
        let tag = try TagService(context: context).findOrCreate(named: "trip")
        let anyEntry = try #require(try context.fetch(FetchDescriptor<LedgerEntry>()).first)
        anyEntry.tags = [tag]
        anyEntry.receiptImage = Data([1, 2, 3])
        try context.save()

        let before = try BackupService.makeBackup(context: context, now: now)
        let data = try BackupService.encode(before)
        try BackupService.eraseAll(context: context)
        #expect(try context.fetchCount(FetchDescriptor<LedgerEntry>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<LedgerCategory>()) == Seeder.expenseCategories.count + Seeder.incomeCategories.count)

        try BackupService.restore(try BackupService.decode(data), context: context)
        let after = try BackupService.makeBackup(context: context, now: now)
        #expect(after.entries.count == before.entries.count)
        #expect(after.entries.map(\.amountMinor).reduce(0, +) == before.entries.map(\.amountMinor).reduce(0, +))
        #expect(after.categories.count == before.categories.count)
        #expect(after.budgets.count == before.budgets.count)
        #expect(after.rules.count == before.rules.count)
        #expect(after.goals.first?.contributions.count == before.goals.first?.contributions.count)
        let restored = try #require(try TransactionService(context: context).entry(id: anyEntry.id))
        #expect(restored.tags?.map(\.name) == ["trip"])
        #expect(restored.receiptImage == Data([1, 2, 3]))
        #expect(restored.category?.id == before.entries.first { $0.id == anyEntry.id }?.categoryID)
    }

    @Test func rejectsForeignAndNewerFiles() throws {
        #expect(throws: BackupError.self) { try BackupService.decode(Data("{}".utf8)) }
        let container = try KnockStore.makeInMemoryContainer()
        var backup = try BackupService.makeBackup(context: container.mainContext)
        backup.version = 99
        #expect(throws: BackupError.self) { try BackupService.decode(try BackupService.encode(backup)) }
    }

    @Test func autoBackupWritesDailyAndKeepsFourteen() throws {
        let container = try KnockStore.makeInMemoryContainer()
        try Seeder.seedIfNeeded(context: container.mainContext)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = calc.calendar
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12)) ?? .now
        for day in 0..<20 {
            let now = calendar.date(byAdding: .day, value: day, to: start) ?? start
            #expect(try AutoBackup.performIfNeeded(context: container.mainContext, directory: directory, now: now, calendar: calendar) != nil)
        }
        #expect(try AutoBackup.performIfNeeded(context: container.mainContext, directory: directory, now: calendar.date(byAdding: .day, value: 19, to: start) ?? start, calendar: calendar) == nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
        #expect(files.count == 14)
        #expect(files.last == "knock-2026-10-20.json")
    }
}
