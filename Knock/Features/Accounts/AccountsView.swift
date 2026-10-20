import KnockKit
import SwiftData
import SwiftUI

/// Wallets with running balances and total net worth.
struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var editing: Account?
    @State private var addsAccount = false
    @State private var transfers = false
    @State private var errorMessage: String?
    @State private var refreshToken = 0

    private var service: AccountService { AccountService(context: context) }
    private var active: [Account] { accounts.filter { !$0.isArchived } }
    private var archived: [Account] { accounts.filter(\.isArchived) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Net worth")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(MoneyFormat.string(minor: netWorth, currencyCode: settings.currencyCode))
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                        .foregroundStyle(netWorth < 0 ? .red : .primary)
                        .contentTransition(.numericText())
                }
                .accessibilityElement(children: .combine)
                .id(refreshToken)
            }

            Section("Accounts") {
                ForEach(active) { account in
                    NavigationLink {
                        AccountDetailView(account: account)
                    } label: {
                        AccountRow(account: account, balanceMinor: service.balanceMinor(of: account))
                    }
                    .swipeActions {
                        Button("Archive", systemImage: "archivebox") { archive(account, true) }
                            .tint(.orange)
                        Button("Edit", systemImage: "pencil") { editing = account }
                    }
                }
                .onMove(perform: move)
            }

            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived) { account in
                        AccountRow(account: account, balanceMinor: service.balanceMinor(of: account))
                            .opacity(0.6)
                            .swipeActions {
                                Button("Restore", systemImage: "arrow.uturn.backward") { archive(account, false) }
                                    .tint(.green)
                            }
                    }
                }
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New account", systemImage: "plus") { addsAccount = true }
                    if active.count > 1 {
                        Button("Transfer between accounts", systemImage: "arrow.left.arrow.right") { transfers = true }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .sheet(isPresented: $addsAccount) { AccountEditor(account: nil) }
        .sheet(item: $editing) { AccountEditor(account: $0) }
        .fullScreenCover(isPresented: $transfers) { QuickEntrySheet(initialKind: .transfer) }
        .onReceive(NotificationCenter.default.publisher(for: StoreEvents.didChange)) { _ in refreshToken += 1 }
        .alert("Couldn't update account", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var netWorth: Int64 {
        _ = refreshToken
        return (try? service.netWorthMinor()) ?? 0
    }

    private func archive(_ account: Account, _ archived: Bool) {
        do { try service.setArchived(account, archived) } catch { errorMessage = error.localizedDescription }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ids = active.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        do { try service.reorder(ids + archived.map(\.id)) } catch { errorMessage = error.localizedDescription }
    }
}

struct AccountRow: View {
    let account: Account
    let balanceMinor: Int64

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(emoji: account.emoji, colorHex: account.colorHex)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.name)
                    if account.isDefault {
                        Text("Default")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: .capsule)
                    }
                }
                Text(kindName(account.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if account.kind == .creditCard {
                    Text(MoneyFormat.string(minor: max(-balanceMinor, 0), currencyCode: account.currencyCode))
                        .monospacedDigit()
                        .foregroundStyle(balanceMinor < 0 ? .red : .primary)
                    Text("Outstanding")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(MoneyFormat.string(minor: balanceMinor, currencyCode: account.currencyCode))
                        .monospacedDigit()
                        .foregroundStyle(balanceMinor < 0 ? .red : .primary)
                }
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

func kindName(_ kind: AccountKind) -> String {
    switch kind {
    case .cash: String(localized: "Cash")
    case .bank: String(localized: "Bank")
    case .creditCard: String(localized: "Credit card")
    case .upiWallet: String(localized: "UPI / Wallet")
    case .savings: String(localized: "Savings")
    case .other: String(localized: "Other")
    }
}

#Preview {
    NavigationStack {
        AccountsView()
    }
    .previewEnvironment()
}
