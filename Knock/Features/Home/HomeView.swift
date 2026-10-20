import KnockKit
import SwiftData
import SwiftUI

/// This cycle at a glance plus the latest entries. Budgets and safe-to-spend join in M5.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(UndoCenter.self) private var undoCenter

    @Query(HomeView.recentDescriptor) private var recent: [LedgerEntry]

    @State private var period: Period?
    @State private var totals = Totals()
    @State private var netWorth: Int64 = 0
    @State private var dataVersion = StoreEvents.dataVersion
    @State private var safe: BudgetMath.SafeToSpend?
    @State private var overall: BudgetStatus?
    @State private var upcoming: [UpcomingItem] = []
    @State private var editing: LedgerEntry?
    @State private var errorMessage: String?

    static var recentDescriptor: FetchDescriptor<LedgerEntry> {
        var descriptor = FetchDescriptor<LedgerEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 10
        return descriptor
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summary
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    if let period {
                        Text(rangeText(period))
                    }
                }

                if let overall {
                    Section {
                        SafeToSpendCard(status: overall, safe: safe, currencyCode: settings.currencyCode)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                if !upcoming.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcoming.prefix(3)) { UpcomingRow(item: $0) }
                    }
                }

                Section {
                    NavigationLink {
                        AccountsView()
                    } label: {
                        LabeledContent("Net worth") {
                            Text(MoneyFormat.string(minor: netWorth, currencyCode: settings.currencyCode, showsFraction: false))
                                .monospacedDigit()
                                .foregroundStyle(netWorth < 0 ? .red : .primary)
                        }
                    }
                }

                Section("Recent") {
                    if recent.isEmpty {
                        ContentUnavailableView("Nothing logged yet", systemImage: "tray", description: Text("Tap + to log an expense. Back Tap logging arrives in M2."))
                    }
                    ForEach(recent) { entry in
                        Button {
                            editing = entry
                        } label: {
                            EntryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(entry) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(period.map { $0.start.formatted(.dateTime.month(.wide)) } ?? String(localized: "Home"))
            .refreshable { refresh() }
            .task(id: settings.cycleStartDay) { refresh() }
            .task(id: dataVersion) {
                // A full pass over the ledger: done off the main thread, once per change.
                netWorth = (try? await AppServices.analytics.netWorth(dataVersion: dataVersion)) ?? netWorth
            }
            .onReceive(NotificationCenter.default.publisher(for: StoreEvents.didChange)) { _ in
                refresh()
                dataVersion = StoreEvents.dataVersion
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in refresh() }
            .sheet(item: $editing) { entry in
                TransactionEditor(entry: entry)
            }
            .floatingAddButton()
            .undoToast()
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            SummaryCard(title: "Spent", minor: totals.netSpendMinor, currencyCode: settings.currencyCode, color: .primary)
                .accessibilityIdentifier("summary-spent")
            SummaryCard(title: "Income", minor: totals.incomeMinor, currencyCode: settings.currencyCode, color: .green)
            SummaryCard(title: "Net", minor: totals.netMinor, currencyCode: settings.currencyCode, color: totals.netMinor < 0 ? .red : .primary, signed: true)
        }
    }

    private func rangeText(_ period: Period) -> String {
        let last = period.end.addingTimeInterval(-1)
        return "\(period.start.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated)))"
    }

    private func refresh() {
        let current = settings.calculator.cycle(containing: .now)
        period = current
        let start = current.start, end = current.end
        let descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.date >= start && $0.date < end })
        do {
            totals = Totals(entries: try context.fetch(descriptor))
            let calculator = settings.calculator
            let recurring = RecurringService(context: context, calculator: calculator)
            let budgets = BudgetService(context: context, calculator: calculator)
            overall = try budgets.statuses().first { $0.categoryID == nil }
            safe = try budgets.safeToSpend(upcomingRecurringMinor: recurring.scheduledSpend(in: current, after: .now))
            upcoming = try recurring.upcoming(days: 7)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ entry: LedgerEntry) {
        let message = deleteMessage(for: entry)
        do {
            let deleted = try TransactionService(context: context, calculator: settings.calculator).delete(entry)
            undoCenter.offer(deleted, message: message)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SafeToSpendCard: View {
    let status: BudgetStatus
    let safe: BudgetMath.SafeToSpend?
    let currencyCode: String

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Safe to spend today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let safe {
                    Text(MoneyFormat.string(minor: safe.leftTodayMinor, currencyCode: currencyCode, showsFraction: false))
                        .font(.title.bold())
                        .monospacedDigit()
                        .foregroundStyle(safe.leftTodayMinor < 0 ? .red : .primary)
                        .contentTransition(.numericText())
                    Text("\(MoneyFormat.string(minor: safe.perDayMinor, currencyCode: currencyCode, showsFraction: false))/day · \(safe.daysRemaining) days left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer()
            BudgetRing(progress: status.progress, isOver: status.isOver)
                .frame(width: 64, height: 64)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

struct SummaryCard: View {
    let title: LocalizedStringKey
    let minor: Int64
    let currencyCode: String
    let color: Color
    var signed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(MoneyFormat.string(minor: minor, currencyCode: currencyCode, sign: signed ? .explicit : .none, showsFraction: false))
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HomeView()
        .previewEnvironment()
}

#Preview("Empty") {
    HomeView()
        .previewEnvironment(empty: true)
}
