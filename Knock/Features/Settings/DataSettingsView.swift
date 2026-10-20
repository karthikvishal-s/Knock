import KnockKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Export / import CSV, JSON backup & restore, automatic backups and erase-all.
struct DataSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    enum ExportRange: String, CaseIterable, Identifiable {
        case all, thisYear, thisCycle
        var id: String { rawValue }
    }

    @State private var exportRange: ExportRange = .all
    @State private var exportFile: DataFile?
    @State private var exportName = ""
    @State private var exportType: UTType = .commaSeparatedText
    @State private var importsCSV = false
    @State private var importsBackup = false
    @State private var csvTable: CSVTable?
    @State private var pendingBackup: KnockBackup?
    @State private var erasing = false
    @State private var eraseText = ""
    @State private var message: String?
    @State private var latestBackup: String?

    var body: some View {
        Form {
            Section {
                Picker("Range", selection: $exportRange) {
                    Text("Everything").tag(ExportRange.all)
                    Text("This year").tag(ExportRange.thisYear)
                    Text("This cycle").tag(ExportRange.thisCycle)
                }
                Button("Export CSV", systemImage: "tablecells") { exportCSV() }
                Button("Import CSV…", systemImage: "square.and.arrow.down") { importsCSV = true }
            } header: {
                Text("Spreadsheet (CSV)")
            } footer: {
                Text("Import from another app or a bank statement — you'll match its columns before anything is saved. Re-importing the same file skips duplicates.")
            }

            Section {
                Button("Export full backup", systemImage: "externaldrive") { exportBackup() }
                Button("Restore from backup…", systemImage: "arrow.counterclockwise") { importsBackup = true }
                LabeledContent("Automatic backup", value: latestBackup ?? String(localized: "Not yet"))
            } header: {
                Text("Backup (JSON)")
            } footer: {
                Text("Knock saves a backup every day you open it (the last 14 are kept). Find them in Files → On My iPhone → Knock → Backups. Keep a copy somewhere safe — deleting the app deletes its data.")
            }

            Section {
                Button("Erase all data", systemImage: "trash", role: .destructive) {
                    eraseText = ""
                    erasing = true
                }
            } footer: {
                Text("Deletes every transaction, account, budget and goal on this iPhone, then restores the default categories.")
            }
        }
        .navigationTitle("Data")
        .task { refreshBackupStatus() }
        .fileExporter(isPresented: Binding { exportFile != nil } set: { if !$0 { exportFile = nil } },
                      document: exportFile, contentType: exportType, defaultFilename: exportName) { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importsCSV, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text]) { result in
            load(result) { data in
                let text = String(decoding: data, as: UTF8.self)
                let table = CSVCodec.parse(text)
                guard table.count > 1 else { throw CSVImportError.empty }
                csvTable = CSVTable(rows: table)
            }
        }
        .fileImporter(isPresented: $importsBackup, allowedContentTypes: [.json]) { result in
            load(result) { data in pendingBackup = try BackupService.decode(data) }
        }
        .sheet(item: $csvTable) { table in
            ImportFlowView(table: table.rows) { result in
                message = String(localized: "Imported \(result.imported). Skipped \(result.skippedDuplicates) duplicates, \(result.failed) unreadable rows.")
            }
        }
        .confirmationDialog("Replace all data with this backup?", isPresented: Binding { pendingBackup != nil } set: { if !$0 { pendingBackup = nil } },
                            titleVisibility: .visible) {
            Button("Replace everything", role: .destructive) {
                guard let backup = pendingBackup else { return }
                do {
                    try BackupService.restore(backup, context: context)
                    message = String(localized: "Restored \(backup.entries.count) transactions from \(backup.exportedAt.formatted(date: .abbreviated, time: .shortened)).")
                } catch {
                    message = error.localizedDescription
                }
            }
        } message: {
            if let backup = pendingBackup {
                Text("Backup from \(backup.exportedAt.formatted(date: .abbreviated, time: .shortened)) with \(backup.entries.count) transactions. Everything currently in Knock will be replaced.")
            }
        }
        .alert("Erase all data?", isPresented: $erasing) {
            TextField("Type ERASE", text: $eraseText)
                .textInputAutocapitalization(.characters)
            Button("Cancel", role: .cancel) {}
            Button("Erase", role: .destructive) {
                guard eraseText == "ERASE" else {
                    message = String(localized: "Nothing was erased. Type ERASE to confirm.")
                    return
                }
                do {
                    try BackupService.eraseAll(context: context)
                    message = String(localized: "All data erased.")
                } catch {
                    message = error.localizedDescription
                }
            }
        } message: {
            Text("This can't be undone. Export a backup first if you might want this data back.")
        }
        .alert("Data", isPresented: Binding { message != nil } set: { if !$0 { message = nil } }) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: Actions

    private func exportCSV() {
        let calc = settings.calculator
        let range: Period? = switch exportRange {
        case .all: nil
        case .thisYear: calc.year(containing: .now)
        case .thisCycle: calc.cycle(containing: .now)
        }
        do {
            let csv = try CSVExporter.export(context: context, from: range?.start ?? .distantPast, to: range?.end ?? .distantFuture)
            exportType = .commaSeparatedText
            exportName = "Knock-\(Date.now.formatted(.iso8601.year().month().day())).csv"
            exportFile = DataFile(data: Data(csv.utf8))
        } catch {
            message = error.localizedDescription
        }
    }

    private func exportBackup() {
        do {
            exportType = .json
            exportName = "Knock-backup-\(Date.now.formatted(.iso8601.year().month().day())).json"
            exportFile = DataFile(data: try BackupService.encode(BackupService.makeBackup(context: context)))
        } catch {
            message = error.localizedDescription
        }
    }

    private func load(_ result: Result<URL, Error>, _ handle: (Data) throws -> Void) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try handle(try Data(contentsOf: url))
        } catch {
            message = error.localizedDescription
        }
    }

    private func refreshBackupStatus() {
        let files = (try? FileManager.default.contentsOfDirectory(at: AutoBackup.directory(), includingPropertiesForKeys: nil)) ?? []
        latestBackup = files.map(\.lastPathComponent).filter { $0.hasPrefix("knock-") }.sorted().last?
            .replacingOccurrences(of: "knock-", with: "").replacingOccurrences(of: ".json", with: "")
    }
}

enum CSVImportError: LocalizedError {
    case empty
    var errorDescription: String? { String(localized: "That file has no rows to import.") }
}

struct CSVTable: Identifiable {
    let id = UUID()
    let rows: [[String]]
}

struct DataFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .commaSeparatedText]
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Column mapping → preview → import.
struct ImportFlowView: View {
    let table: [[String]]
    var onFinish: (ImportResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var mapping: CSVImportMapping
    @State private var errorMessage: String?

    init(table: [[String]], onFinish: @escaping (ImportResult) -> Void) {
        self.table = table
        self.onFinish = onFinish
        _mapping = State(initialValue: CSVImporter.guessMapping(header: table.first ?? []))
    }

    private var columns: [String] {
        let header = table.first ?? []
        return mapping.hasHeader ? header : header.indices.map { String(localized: "Column \($0 + 1)") }
    }

    private var rows: [ImportRow] {
        CSVImporter.rows(from: table, mapping: mapping, defaultCurrency: settings.currencyCode)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("First row is a header", isOn: $mapping.hasHeader)
                    columnPicker("Date", $mapping.date, required: true)
                    columnPicker("Amount", $mapping.amount)
                    if mapping.amount == nil {
                        columnPicker("Debit (money out)", $mapping.debit)
                        columnPicker("Credit (money in)", $mapping.credit)
                    }
                    columnPicker("Type", $mapping.type)
                    columnPicker("Category", $mapping.category)
                    columnPicker("Account", $mapping.account)
                    columnPicker("Payee / description", $mapping.payee)
                    columnPicker("Note", $mapping.note)
                    columnPicker("Tags", $mapping.tags)
                } header: {
                    Text("Match columns")
                }

                Section {
                    Picker("Date format", selection: Binding($mapping.dateFormat, default: detectedFormat)) {
                        ForEach(["iso8601"] + CSVImporter.dateFormats, id: \.self) { format in
                            Text(format == detectedFormat ? "\(format) (detected)" : format).tag(format)
                        }
                    }
                    if mapping.amount != nil, mapping.type == nil {
                        Picker("Positive amounts are", selection: $mapping.positiveMeans) {
                            Text("Expenses").tag(CSVImportMapping.PositiveAmounts.expense)
                            Text("Income").tag(CSVImportMapping.PositiveAmounts.income)
                        }
                    }
                }

                Section {
                    let preview = rows
                    let failures = preview.filter { $0.error != nil }.count
                    Text("\(preview.count - failures) ready · \(failures) with problems")
                        .font(.subheadline)
                        .foregroundStyle(failures > 0 ? .orange : .secondary)
                    ForEach(preview.prefix(15)) { row in
                        ImportPreviewRow(row: row)
                    }
                } header: {
                    Text("Preview")
                }
            }
            .navigationTitle("Import CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", role: .confirm, action: commit).disabled(!mapping.isUsable)
                }
            }
            .alert("Import failed", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var detectedFormat: String {
        let samples = (mapping.hasHeader ? table.dropFirst() : table[...]).compactMap { row in mapping.date.flatMap { $0 < row.count ? row[$0] : nil } }
        return CSVImporter.detectDateFormat(Array(samples)) ?? "yyyy-MM-dd"
    }

    private func columnPicker(_ title: LocalizedStringKey, _ selection: Binding<Int?>, required: Bool = false) -> some View {
        Picker(title, selection: selection) {
            Text(required ? "Choose…" : "Not in file").tag(Int?.none)
            ForEach(Array(columns.enumerated()), id: \.offset) { index, name in
                Text(name.isEmpty ? String(localized: "Column \(index + 1)") : name).tag(Optional(index))
            }
        }
    }

    private func commit() {
        do {
            let result = try CSVImporter.commit(rows, context: context, calculator: settings.calculator)
            onFinish(result)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ImportPreviewRow: View {
    let row: ImportRow

    private var amountText: String {
        let signed = row.kind == .expense ? -row.amount : row.amount
        return MoneyFormat.string(Money(amount: signed, currencyCode: row.currencyCode), sign: .explicit)
    }

    private var details: String {
        [row.category, row.payee, row.note].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(row.date?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                Spacer()
                Text(amountText)
                    .monospacedDigit()
                    .foregroundStyle(row.kind == .expense ? Color.primary : Color.green)
            }
            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = row.error {
                Text("Line \(row.line): \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
