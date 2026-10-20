import KnockKit
import SwiftData
import SwiftUI

/// The full form for editing an existing entry (or adding one with every field).
struct TransactionEditor: View {
    let entry: LedgerEntry?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(UndoCenter.self) private var undoCenter

    @Query(filter: #Predicate<LedgerCategory> { !$0.isArchived }, sort: \LedgerCategory.sortOrder)
    private var categories: [LedgerCategory]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder)
    private var accounts: [Account]

    @State private var draft: TransactionDraft
    @State private var amount: Decimal?
    @State private var confirmsDelete = false
    @State private var errorMessage: String?

    init(entry: LedgerEntry?) {
        self.entry = entry
        let draft = entry.map(TransactionDraft.init(entry:)) ?? TransactionDraft(currencyCode: AppSettings.shared.currencyCode)
        _draft = State(initialValue: draft)
        _amount = State(initialValue: entry == nil ? nil : draft.amount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $draft.kind) {
                        Text("Expense").tag(TransactionKind.expense)
                        Text("Refund").tag(TransactionKind.refund)
                        Text("Income").tag(TransactionKind.income)
                        Text("Transfer").tag(TransactionKind.transfer)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    TextField("Amount", value: $amount, format: .number.precision(.fractionLength(0...CurrencyCatalog.minorUnitDigits(for: draft.currencyCode))))
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .accessibilityIdentifier("editor-amount")
                }

                Section {
                    if draft.kind == .transfer {
                        accountPicker("From", selection: $draft.accountID)
                        accountPicker("To", selection: $draft.transferAccountID)
                    } else {
                        Picker("Category", selection: $draft.categoryID) {
                            Text("None").tag(UUID?.none)
                            ForEach(categoriesForKind) { category in
                                Text(category.displayName).tag(Optional(category.id))
                            }
                        }
                        accountPicker("Account", selection: $draft.accountID)
                    }
                    DatePicker("Date", selection: $draft.date)
                }

                Section {
                    TextField("Payee or merchant", text: $draft.payee)
                        .textInputAutocapitalization(.words)
                    TextField("Note", text: $draft.note, axis: .vertical)
                        .lineLimit(1...4)
                }

                if let entry {
                    Section {
                        Button("Duplicate as today", systemImage: "plus.square.on.square") {
                            perform { try service.duplicate(entry) }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            confirmsDelete = true
                        }
                        .accessibilityIdentifier("editor-delete")
                    } footer: {
                        Text("Added \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
            }
            .navigationTitle(entry == nil ? "New Transaction" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm, action: save)
                        .disabled((amount ?? 0) <= 0)
                        .accessibilityIdentifier("editor-save")
                }
            }
            .onChange(of: draft.kind) { _, kind in
                if let id = draft.categoryID, categories.first(where: { $0.id == id })?.kind != kind.categoryKind {
                    draft.categoryID = nil
                }
            }
            .confirmationDialog("Delete this transaction?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
            }
            .alert("Couldn't save", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var service: TransactionService {
        TransactionService(context: context, calculator: settings.calculator)
    }

    private var categoriesForKind: [LedgerCategory] {
        guard let kind = draft.kind.categoryKind else { return [] }
        return categories.filter { $0.kind == kind }
    }

    private func accountPicker(_ title: LocalizedStringKey, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            ForEach(accounts) { account in
                Text(account.displayName).tag(Optional(account.id))
            }
        }
    }

    private func save() {
        var final = draft
        final.amount = amount ?? 0
        perform {
            if let entry {
                try service.update(entry, with: final)
            } else {
                try service.add(final)
            }
        }
    }

    private func delete() {
        guard let entry else { return }
        let message = deleteMessage(for: entry)
        perform {
            let deleted = try service.delete(entry)
            undoCenter.offer(deleted, message: message)
        }
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

func deleteMessage(for entry: LedgerEntry) -> String {
    let amount = MoneyFormat.string(minor: entry.amountMinor, currencyCode: entry.currencyCode)
    let name = entry.category?.name ?? (entry.kind == .transfer ? String(localized: "Transfer") : "")
    return name.isEmpty ? String(localized: "Deleted \(amount)") : String(localized: "Deleted \(amount) · \(name)")
}

#Preview("Edit") {
    TransactionEditor(entry: PreviewData.anyEntry)
        .previewEnvironment()
}

#Preview("New") {
    TransactionEditor(entry: nil)
        .previewEnvironment()
}
