import Foundation
import SwiftData

// MARK: - Export

public enum CSVExporter {
    public static let header = ["Date", "Type", "Amount", "Currency", "Category", "Parent Category", "Account", "To Account", "Payee", "Note", "Tags"]

    /// All entries in `[start, end)`, oldest first, in Knock's own column layout.
    public static func export(context: ModelContext, from start: Date = .distantPast, to end: Date = .distantFuture) throws -> String {
        var descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.date >= start && $0.date < end }, sortBy: [SortDescriptor(\.date)])
        descriptor.relationshipKeyPathsForPrefetching = [\.category, \.account, \.transferAccount, \.tags]
        let entries = try context.fetch(descriptor)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let rows = entries.map { entry -> [String] in
            [
                dateFormatter.string(from: entry.date),
                entry.kindRaw,
                NSDecimalNumber(decimal: entry.money.amount).stringValue,
                entry.currencyCode,
                entry.category?.name ?? "",
                entry.category?.parent?.name ?? "",
                entry.account?.name ?? "",
                entry.transferAccount?.name ?? "",
                entry.payee,
                entry.note,
                (entry.tags ?? []).map(\.name).sorted().joined(separator: "; "),
            ]
        }
        return CSVCodec.encode([header] + rows)
    }
}

// MARK: - Import

public struct CSVImportMapping: Equatable, Sendable {
    public enum PositiveAmounts: String, Sendable, CaseIterable {
        /// Most expense apps: every amount is positive, the type column says which.
        case expense
        /// Bank statements: money in is positive, money out negative.
        case income
    }

    public var hasHeader = true
    public var date: Int?
    public var amount: Int?
    /// Separate debit / credit columns (bank statements) instead of one amount column.
    public var debit: Int?
    public var credit: Int?
    public var type: Int?
    public var category: Int?
    public var account: Int?
    public var payee: Int?
    public var note: Int?
    public var tags: Int?
    public var currency: Int?
    public var dateFormat: String?
    public var positiveMeans: PositiveAmounts = .expense

    public init() {}

    public var isUsable: Bool { date != nil && (amount != nil || debit != nil || credit != nil) }
}

public struct ImportRow: Identifiable, Sendable {
    public var id: Int { line }
    public var line: Int
    public var date: Date?
    public var kind: TransactionKind
    public var amount: Decimal
    public var currencyCode: String
    public var category: String
    public var account: String
    public var payee: String
    public var note: String
    public var tags: [String]
    public var error: String?
}

public struct ImportResult: Equatable, Sendable {
    public var imported = 0
    public var skippedDuplicates = 0
    public var failed = 0
    public var createdCategories = 0
    public var createdAccounts = 0
}

public enum CSVImporter {
    public static let dateFormats = [
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd",
        "dd/MM/yyyy HH:mm", "dd/MM/yyyy", "d/M/yyyy", "dd-MM-yyyy", "dd.MM.yyyy", "dd/MM/yy",
        "MM/dd/yyyy HH:mm", "MM/dd/yyyy", "d MMM yyyy", "dd MMM yyyy", "d-MMM-yy", "MMM d, yyyy",
    ]

    /// Guesses columns from header names (Knock's own export maps exactly).
    public static func guessMapping(header: [String]) -> CSVImportMapping {
        var mapping = CSVImportMapping()
        func find(_ names: [String]) -> Int? {
            header.firstIndex { cell in
                let key = cell.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                return names.contains { key == $0 } || names.contains { key.hasPrefix($0 + " ") }
            }
        }
        mapping.date = find(["date", "transaction date", "txn date", "value date", "time", "datetime"])
        mapping.amount = find(["amount", "value", "amt", "inr", "sum"])
        mapping.debit = find(["debit", "withdrawal", "withdrawal amt.", "withdrawal amount", "dr", "paid out", "money out"])
        mapping.credit = find(["credit", "deposit", "deposit amt.", "deposit amount", "cr", "paid in", "money in"])
        if mapping.amount != nil { mapping.debit = nil; mapping.credit = nil }
        mapping.type = find(["type", "transaction type", "kind", "income/expense", "dr/cr"])
        mapping.category = find(["category", "categories"])
        mapping.account = find(["account", "wallet", "payment mode", "mode"])
        mapping.payee = find(["payee", "merchant", "description", "narration", "particulars", "title", "name"])
        mapping.note = find(["note", "notes", "memo", "remarks", "comment"])
        mapping.tags = find(["tags", "tag", "labels"])
        mapping.currency = find(["currency"])
        if mapping.payee == mapping.note { mapping.note = nil }
        return mapping
    }

    /// The first format that parses every non-empty sample *and* formats it back to the same
    /// text — `DateFormatter` alone happily reads "5 Oct 2026" as dd/MM/yyyy.
    public static func detectDateFormat(_ samples: [String]) -> String? {
        let values = samples.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(50)
        guard !values.isEmpty else { return nil }
        if values.allSatisfy({ ISO8601DateFormatter().date(from: $0) != nil }) { return "iso8601" }
        return dateFormats.first { format in
            let formatter = makeFormatter(format, timeZone: .current)
            return values.allSatisfy { value in
                guard let date = formatter.date(from: value) else { return false }
                return formatter.string(from: date).caseInsensitiveCompare(value) == .orderedSame
            }
        }
    }

    /// Accepts "₹1,23,456.78", "-250", "(250.00)", "250 Dr", "1.234,56" (when `.` is a grouping separator).
    public static func parseAmount(_ raw: String) -> Decimal? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var negative = false
        if text.hasPrefix("(") && text.hasSuffix(")") { negative = true; text = String(text.dropFirst().dropLast()) }
        let upper = text.uppercased()
        if upper.hasSuffix("DR") { negative = true; text = String(text.dropLast(2)) } else if upper.hasSuffix("CR") { text = String(text.dropLast(2)) }
        if text.contains("-") || text.contains("−") { negative = true }
        var cleaned = text.filter { $0.isNumber || $0 == "." || $0 == "," }
        // "1.234,56" → decimal comma; otherwise commas are grouping.
        if let comma = cleaned.lastIndex(of: ","), let dot = cleaned.lastIndex(of: "."), comma > dot {
            cleaned = cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if !cleaned.contains("."), let comma = cleaned.lastIndex(of: ","), cleaned.distance(from: comma, to: cleaned.endIndex) == 3, cleaned.filter({ $0 == "," }).count == 1 {
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        } else {
            cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        }
        guard !cleaned.isEmpty, let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return negative ? -value : value
    }

    static func kind(from raw: String) -> TransactionKind? {
        switch raw.lowercased().trimmingCharacters(in: .whitespaces) {
        case "expense", "expenses", "debit", "dr", "withdrawal", "out", "spent", "payment": .expense
        case "income", "credit", "cr", "deposit", "in", "received", "salary": .income
        case "refund", "credit/refund", "cashback", "reversal": .refund
        case "transfer", "self transfer": .transfer
        default: nil
        }
    }

    public static func rows(from table: [[String]], mapping: CSVImportMapping, defaultCurrency: String, timeZone: TimeZone = .current) -> [ImportRow] {
        let body = mapping.hasHeader ? Array(table.dropFirst()) : table
        let format = mapping.dateFormat ?? detectDateFormat(body.compactMap { row in mapping.date.flatMap { $0 < row.count ? row[$0] : nil } }) ?? "yyyy-MM-dd"
        let formatter = format == "iso8601" ? nil : makeFormatter(format, timeZone: timeZone)
        let iso = ISO8601DateFormatter()

        return body.enumerated().map { index, row in
            func cell(_ column: Int?) -> String {
                guard let column, column < row.count else { return "" }
                return row[column].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let line = index + (mapping.hasHeader ? 2 : 1)
            let dateText = cell(mapping.date)
            let date = formatter?.date(from: dateText) ?? (format == "iso8601" ? iso.date(from: dateText) : nil)

            // Amount and sign.
            var signed: Decimal?
            if mapping.amount != nil {
                signed = parseAmount(cell(mapping.amount))
            } else {
                let debit = parseAmount(cell(mapping.debit)).map { $0 < 0 ? -$0 : $0 }
                let credit = parseAmount(cell(mapping.credit)).map { $0 < 0 ? -$0 : $0 }
                if let debit, debit != 0 { signed = -debit } else if let credit, credit != 0 { signed = credit }
            }
            // Kind: an explicit type column wins (a negative expense is a refund). Otherwise the
            // sign decides: debit/credit columns and bank-style files read negative as spending;
            // expense-app files (positives are expenses) read negative as a refund.
            let isNegative = (signed ?? 0) < 0
            let resolvedKind: TransactionKind
            if let explicit = kind(from: cell(mapping.type)) {
                resolvedKind = explicit == .expense && isNegative ? .refund : explicit
            } else if mapping.amount == nil || mapping.positiveMeans == .income {
                resolvedKind = isNegative ? .expense : .income
            } else {
                resolvedKind = isNegative ? .refund : .expense
            }
            let magnitude = signed.map { $0 < 0 ? -$0 : $0 } ?? 0

            var error: String?
            if date == nil { error = String(localized: "Can't read the date “\(dateText)”.") }
            else if signed == nil || magnitude == 0 { error = String(localized: "No amount.") }
            else if resolvedKind == .transfer { error = String(localized: "Transfers can't be imported; add them in the app.") }

            let currency = cell(mapping.currency).uppercased()
            return ImportRow(
                line: line, date: date, kind: resolvedKind, amount: magnitude,
                currencyCode: currency.count == 3 ? currency : defaultCurrency,
                category: cell(mapping.category), account: cell(mapping.account), payee: cell(mapping.payee), note: cell(mapping.note),
                tags: cell(mapping.tags).split(whereSeparator: { $0 == ";" || $0 == "," || $0 == "|" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                error: error
            )
        }
    }

    /// Inserts valid rows, creating missing categories, accounts and tags. Rows matching an
    /// existing entry (same day, kind, amount and payee/note) are skipped, so re-importing
    /// the same file is harmless.
    public static func commit(_ rows: [ImportRow], context: ModelContext, calculator: PeriodCalculator) throws -> ImportResult {
        var result = ImportResult()
        var categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        var accounts = try context.fetch(FetchDescriptor<Account>())
        let tags = TagService(context: context)
        let existing = try context.fetch(FetchDescriptor<LedgerEntry>())
        var fingerprints = Set(existing.map { fingerprint(dayKey: $0.dayKey, kind: $0.kind, amountMinor: $0.amountMinor, payee: $0.payee, note: $0.note) })
        let service = TransactionService(context: context, calculator: calculator)

        for row in rows {
            guard row.error == nil, let date = row.date, let categoryKind = row.kind.categoryKind else {
                result.failed += 1
                continue
            }
            let amountMinor = Money(amount: row.amount, currencyCode: row.currencyCode).minorUnits
            let print = fingerprint(dayKey: calculator.dayKey(for: date), kind: row.kind, amountMinor: amountMinor, payee: row.payee, note: row.note)
            guard !fingerprints.contains(print) else {
                result.skippedDuplicates += 1
                continue
            }

            var categoryID: UUID?
            if !row.category.isEmpty {
                if let match = categories.first(where: { $0.kind == categoryKind && $0.name.localizedCaseInsensitiveCompare(row.category) == .orderedSame }) {
                    categoryID = match.id
                } else {
                    let order = (categories.filter { $0.kind == categoryKind }.map(\.sortOrder).max() ?? -1) + 1
                    let created = LedgerCategory(name: row.category, emoji: "🏷️", colorHex: "#8E8E93", kind: categoryKind, sortOrder: order)
                    context.insert(created)
                    categories.append(created)
                    categoryID = created.id
                    result.createdCategories += 1
                }
            }
            var accountID: UUID?
            if !row.account.isEmpty {
                if let match = accounts.first(where: { $0.name.localizedCaseInsensitiveCompare(row.account) == .orderedSame }) {
                    accountID = match.id
                } else {
                    let created = Account(name: row.account, kind: .other, emoji: AccountKind.other.defaultEmoji, colorHex: "#8E8E93",
                                          currencyCode: row.currencyCode, sortOrder: (accounts.map(\.sortOrder).max() ?? -1) + 1)
                    context.insert(created)
                    accounts.append(created)
                    accountID = created.id
                    result.createdAccounts += 1
                }
            }
            let tagIDs = try row.tags.map { try tags.findOrCreate(named: $0).id }
            let draft = TransactionDraft(kind: row.kind, amount: row.amount, currencyCode: row.currencyCode, categoryID: categoryID, accountID: accountID,
                                         date: date, note: row.note, payee: row.payee, source: .importFile, tagIDs: tagIDs)
            do {
                try service.add(draft)
                fingerprints.insert(print)
                result.imported += 1
            } catch {
                result.failed += 1
            }
        }
        return result
    }

    static func fingerprint(dayKey: Int32, kind: TransactionKind, amountMinor: Int64, payee: String, note: String) -> String {
        "\(dayKey)|\(kind.rawValue)|\(amountMinor)|\(payee.lowercased())|\(note.lowercased())"
    }

    static func makeFormatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }
}
