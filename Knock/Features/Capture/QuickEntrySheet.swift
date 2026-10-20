import KnockKit
import SwiftData
import SwiftUI

/// Full-screen fast capture: big amount, ranked category tiles, glass keypad.
struct QuickEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @Query(filter: #Predicate<LedgerCategory> { !$0.isArchived }, sort: \LedgerCategory.sortOrder)
    private var allCategories: [LedgerCategory]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder)
    private var accounts: [Account]

    @State private var model: QuickEntryModel
    @State private var savedCount = 0
    @State private var errorMessage: String?
    @FocusState private var noteFocused: Bool

    init(initialKind: TransactionKind) {
        _model = State(initialValue: QuickEntryModel(kind: initialKind, currencyCode: AppSettings.shared.currencyCode))
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Fixed layout at normal sizes; at accessibility sizes the top scrolls while the keypad
        // and Save stay pinned, and text is capped where a bigger size can't fit a keypad key.
        VStack(spacing: 14) {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    kindPicker
                    amountDisplay
                    if model.kind == .transfer {
                        transferAccounts
                    } else {
                        CategoryGrid(categories: rankedCategories, selection: $model.categoryID,
                                     columns: typeSize.isAccessibilitySize ? 3 : 4)
                    }
                    detailsRow
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 14) {
                KeypadView(input: $model.input)
                saveButton
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
        .onAppear { model.prepare(accounts: accounts) }
        .sensoryFeedback(.selection, trigger: model.input) { _, _ in settings.hapticsEnabled }
        .sensoryFeedback(.success, trigger: savedCount) { _, _ in settings.hapticsEnabled }
        .alert("Couldn't save", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Sections

    private var header: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
        return layout {
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityIdentifier("quick-entry-close")
            if !stacked { Spacer() }
            DatePicker("Date", selection: $model.date, in: ...Date.now.addingTimeInterval(365 * 86_400))
                .labelsHidden()
                .datePickerStyle(.compact)
        }
    }

    private var kindPicker: some View {
        Picker("Type", selection: $model.kind) {
            Text("Expense").tag(TransactionKind.expense)
            Text("Income").tag(TransactionKind.income)
            if accounts.count > 1 {
                Text("Transfer").tag(TransactionKind.transfer)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("kind-picker")
    }

    private var amountDisplay: some View {
        VStack(spacing: 6) {
            Text(verbatim: amountText)
                .font(.system(size: 54, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(model.isInflow ? .green : model.input.isEmpty ? .secondary : .primary)
                .contentTransition(.numericText())
                .animation(.snappy, value: model.input)
                .accessibilityLabel("Amount \(amountText)")
                .accessibilityIdentifier("amount-display")
            if model.kind == .expense {
                Toggle(isOn: $model.isCredit) {
                    Label("Credit / refund", systemImage: "arrow.uturn.backward")
                        .font(.subheadline)
                }
                .toggleStyle(.button)
                .buttonStyle(.glass)
                .tint(.green)
                .accessibilityIdentifier("credit-toggle")
            }
        }
    }

    private var transferAccounts: some View {
        HStack(spacing: 8) {
            accountMenu(title: "From", selection: $model.accountID)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            accountMenu(title: "To", selection: $model.transferAccountID)
        }
    }

    private var detailsRow: some View {
        HStack(spacing: 8) {
            if model.kind != .transfer, accounts.count > 1 {
                accountMenu(title: "Account", selection: $model.accountID)
                    .fixedSize()
            }
            TextField("Add note…", text: $model.note)
                .focused($noteFocused)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .glassEffect(.regular, in: .capsule)
                .accessibilityIdentifier("note-field")
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(model.input.isPositive ? "Save \(MoneyFormat.string(Money(amount: model.amount, currencyCode: model.currencyCode)))" : "Save")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.glassProminent)
        .disabled(!model.canSave)
        .accessibilityHint(model.missingRequirement ?? "")
        .accessibilityIdentifier("save-button")
    }

    private func accountMenu(title: LocalizedStringKey, selection: Binding<UUID?>) -> some View {
        Menu {
            Picker(title, selection: selection) {
                ForEach(accounts) { account in
                    Text(account.displayName).tag(Optional(account.id))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(accounts.first { $0.id == selection.wrappedValue }?.displayName ?? String(localized: "Account"))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .frame(maxWidth: model.kind == .transfer ? .infinity : nil)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel(Text(title))
    }

    // MARK: Logic

    private var rankedCategories: [LedgerCategory] {
        guard let kind = model.kind.categoryKind else { return [] }
        return CategoryRanking.ranked(allCategories.filter { $0.kind == kind })
    }

    private var amountText: String {
        let symbol = MoneyFormat.symbol(for: model.currencyCode)
        let sign = model.isInflow && model.input.isPositive ? "+" : ""
        return sign + symbol + model.input.display()
    }

    private func save() {
        do {
            try TransactionService(context: context, calculator: settings.calculator).add(model.draft)
            savedCount += 1
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("Expense") {
    QuickEntrySheet(initialKind: .expense)
        .previewEnvironment()
}

#Preview("Income") {
    QuickEntrySheet(initialKind: .income)
        .previewEnvironment()
}
