import KnockKit
import SwiftData
import SwiftUI

/// Edits a copy of the History filter; Apply writes it back.
struct FilterSheet: View {
    @Binding var filter: HistoryFilter
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var working = HistoryFilter()
    @State private var usesDates = false
    @State private var fromDate = Date.now.addingTimeInterval(-30 * 86_400)
    @State private var throughDate = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    ForEach(TransactionKind.allCases) { kind in
                        toggleRow(title(for: kind), isOn: working.kinds.contains(kind)) {
                            working.kinds.formSymmetricDifference([kind])
                        }
                    }
                }

                Section("Categories") {
                    NavigationLink {
                        MultiSelectList(
                            title: "Categories",
                            groups: [
                                ("Expense", categories.filter { $0.kind == .expense }.map { ($0.id, $0.displayName) }),
                                ("Income", categories.filter { $0.kind == .income }.map { ($0.id, $0.displayName) }),
                            ],
                            selection: $working.categoryIDs
                        )
                    } label: {
                        LabeledContent("Categories", value: summary(working.categoryIDs.count))
                    }
                    NavigationLink {
                        MultiSelectList(title: "Accounts", groups: [("", accounts.map { ($0.id, $0.displayName) })], selection: $working.accountIDs)
                    } label: {
                        LabeledContent("Accounts", value: summary(working.accountIDs.count))
                    }
                }

                Section("Date") {
                    Toggle("Limit dates", isOn: $usesDates.animation())
                    if usesDates {
                        DatePicker("From", selection: $fromDate, displayedComponents: .date)
                        DatePicker("Through", selection: $throughDate, in: fromDate..., displayedComponents: .date)
                    }
                }

                Section {
                    TextField("Minimum", value: $working.minAmount, format: .number)
                        .keyboardType(.decimalPad)
                    TextField("Maximum", value: $working.maxAmount, format: .number)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Amount (\(MoneyFormat.symbol(for: settings.currencyCode)))")
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        working = HistoryFilter()
                        working.searchText = filter.searchText
                        usesDates = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", role: .confirm, action: apply)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        working = filter
        if let range = filter.dateRange {
            usesDates = true
            fromDate = range.start
            throughDate = range.end.addingTimeInterval(-1)
        }
    }

    private func apply() {
        working.dateRange = usesDates ? settings.calculator.custom(from: fromDate, through: throughDate) : nil
        filter = working
        dismiss()
    }

    private func summary(_ count: Int) -> String {
        count == 0 ? String(localized: "Any") : String(localized: "\(count) selected")
    }

    private func title(for kind: TransactionKind) -> LocalizedStringKey {
        switch kind {
        case .expense: "Expense"
        case .income: "Income"
        case .refund: "Refund"
        case .transfer: "Transfer"
        }
    }

    private func toggleRow(_ title: LocalizedStringKey, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct MultiSelectList: View {
    let title: LocalizedStringKey
    let groups: [(title: LocalizedStringKey, items: [(id: UUID, name: String)])]
    @Binding var selection: Set<UUID>

    var body: some View {
        List {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                Section(group.title) {
                    ForEach(group.items, id: \.id) { item in
                        Button {
                            selection.formSymmetricDifference([item.id])
                        } label: {
                            HStack {
                                Text(item.name).foregroundStyle(.primary)
                                Spacer()
                                if selection.contains(item.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            if !selection.isEmpty {
                Button("Clear") { selection = [] }
            }
        }
    }
}

#Preview {
    @Previewable @State var filter = HistoryFilter()
    FilterSheet(filter: $filter)
        .previewEnvironment()
}
