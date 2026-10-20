import KnockKit
import SwiftData
import SwiftUI

struct AccountEditor: View {
    let account: Account?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @State private var draft: AccountDraft
    @State private var hasOpeningDate: Bool
    @State private var errorMessage: String?

    init(account: Account?) {
        self.account = account
        let draft = account.map(AccountDraft.init(account:)) ?? AccountDraft(currencyCode: AppSettings.shared.currencyCode)
        _draft = State(initialValue: draft)
        _hasOpeningDate = State(initialValue: draft.openingDate != .distantPast)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                    Picker("Type", selection: $draft.kind) {
                        ForEach(AccountKind.allCases) { kind in
                            Text("\(kind.defaultEmoji) \(kindName(kind))").tag(kind)
                        }
                    }
                }

                Section("Icon") {
                    EmojiField(emoji: $draft.emoji, suggestions: ["💵", "🏦", "💳", "📱", "🐷", "👛", "🪙", "💰", "🏧", "🧾"])
                    ColorPaletteGrid(selection: $draft.colorHex)
                }

                Section {
                    TextField("Opening balance", value: $draft.openingBalance, format: .number)
                        .keyboardType(.numbersAndPunctuation)
                    Toggle("Starts on a date", isOn: $hasOpeningDate)
                    if hasOpeningDate {
                        DatePicker("Opening date", selection: openingDate, displayedComponents: .date)
                    }
                    if draft.kind == .creditCard {
                        TextField("Credit limit", value: $draft.creditLimit, format: .number)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("Balance (\(MoneyFormat.symbol(for: draft.currencyCode)))")
                } footer: {
                    Text(draft.kind == .creditCard
                         ? "For a card, enter what you owe as a negative opening balance (e.g. −12000)."
                         : "The balance on the opening date. Transactions before it don't change this account's balance.")
                }
            }
            .navigationTitle(account == nil ? "New Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm, action: save)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: draft.kind) { old, new in
                if draft.emoji == old.defaultEmoji { draft.emoji = new.defaultEmoji }
            }
            .alert("Couldn't save", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var openingDate: Binding<Date> {
        Binding { draft.openingDate == .distantPast ? .now : draft.openingDate } set: { draft.openingDate = Calendar.current.startOfDay(for: $0) }
    }

    private func save() {
        var final = draft
        if !hasOpeningDate { final.openingDate = .distantPast }
        let service = AccountService(context: context)
        do {
            if let account {
                try service.update(account, with: final)
            } else {
                try service.add(final)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// An account's balance and its transactions, newest first.
struct AccountDetailView: View {
    let account: Account

    @Environment(\.modelContext) private var context
    @State private var editing: LedgerEntry?
    @State private var editsAccount = false
    @State private var refreshToken = 0

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.kind == .creditCard ? "Outstanding" : "Balance")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(MoneyFormat.string(minor: account.kind == .creditCard ? -balance : balance, currencyCode: account.currencyCode))
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                    if account.kind == .creditCard, let limit = account.creditLimitMinor, limit > 0 {
                        Gauge(value: Double(max(-balance, 0)), in: 0...Double(limit)) {
                            Text("Limit used")
                        } currentValueLabel: {
                            Text(MoneyFormat.string(minor: limit + balance, currencyCode: account.currencyCode) + " available")
                        }
                        .tint(Color(hex: account.colorHex))
                    }
                }
                .id(refreshToken)
            }

            Section("Transactions") {
                if entries.isEmpty {
                    Text("No transactions in this account yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries.prefix(300)) { entry in
                    Button { editing = entry } label: { EntryRow(entry: entry) }
                        .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(account.displayName)
        .toolbar {
            Button("Edit") { editsAccount = true }
        }
        .sheet(item: $editing) { TransactionEditor(entry: $0) }
        .sheet(isPresented: $editsAccount) { AccountEditor(account: account) }
        .onReceive(NotificationCenter.default.publisher(for: StoreEvents.didChange)) { _ in refreshToken += 1 }
    }

    private var balance: Int64 {
        _ = refreshToken
        return AccountService(context: context).balanceMinor(of: account)
    }

    private var entries: [LedgerEntry] {
        _ = refreshToken
        return ((account.entries ?? []) + (account.incomingTransfers ?? [])).sorted { $0.date > $1.date }
    }
}
