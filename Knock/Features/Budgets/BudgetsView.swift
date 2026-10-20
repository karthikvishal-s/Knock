import KnockKit
import SwiftData
import SwiftUI

/// Budgets tab: overall budget with safe-to-spend, category budgets, upcoming bills,
/// recurring rules and savings goals.
struct BudgetsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \SavingsGoal.name) private var goals: [SavingsGoal]

    @State private var statuses: [BudgetStatus] = []
    @State private var safe: BudgetMath.SafeToSpend?
    @State private var upcoming: [UpcomingItem] = []
    @State private var editing: BudgetEditor.Target?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                overallSection
                categorySection
                upcomingSection
                Section {
                    NavigationLink { RecurringListView() } label: { Label("Recurring transactions", systemImage: "arrow.triangle.2.circlepath") }
                }
                goalsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Budgets")
            .toolbar {
                Menu {
                    Button("Monthly budget", systemImage: "indianrupeesign.circle") { editing = .overall }
                    Button("Category budget", systemImage: "square.grid.2x2") { editing = .newCategory }
                    Button("Recurring transaction", systemImage: "arrow.triangle.2.circlepath") { editing = .rule }
                    Button("Savings goal", systemImage: "target") { editing = .goal }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            .task(id: settings.cycleStartDay) { refresh() }
            .onReceive(NotificationCenter.default.publisher(for: StoreEvents.didChange)) { _ in refresh() }
            .refreshable { refresh() }
            .sheet(item: $editing) { target in
                switch target {
                case .rule: RuleEditor(rule: nil)
                case .goal: GoalEditor()
                default: BudgetEditor(target: target)
                }
            }
            .alert("Something went wrong", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var overallSection: some View {
        Section {
            if let overall = statuses.first(where: { $0.categoryID == nil }) {
                Button { editing = .overall } label: {
                    HStack(spacing: 16) {
                        BudgetRing(progress: overall.progress, isOver: overall.isOver)
                            .frame(width: 84, height: 84)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(money(overall.spentMinor)) of \(money(overall.availableMinor))")
                                .font(.headline)
                                .monospacedDigit()
                            if overall.rolloverMinor > 0 {
                                Text("incl. \(money(overall.rolloverMinor)) rolled over")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let safe {
                                Label {
                                    Text("\(money(safe.perDayMinor))/day · \(safe.daysRemaining) days left")
                                } icon: {
                                    Image(systemName: "checkmark.shield")
                                }
                                .font(.subheadline)
                                .foregroundStyle(safe.leftTodayMinor < 0 ? .orange : .secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            } else {
                Button { editing = .overall } label: {
                    Label("Set a monthly budget", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("This cycle")
        } footer: {
            if safe != nil {
                Text("Safe to spend = what's left of the budget, minus bills still due, split over the remaining days.")
            }
        }
    }

    @ViewBuilder
    private var categorySection: some View {
        let categoryStatuses = statuses.filter { $0.categoryID != nil }
        if !categoryStatuses.isEmpty {
            Section("Categories") {
                ForEach(categoryStatuses) { status in
                    Button { editing = .category(status.categoryID) } label: { BudgetRow(status: status, currencyCode: settings.currencyCode) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        if !upcoming.isEmpty {
            Section("Upcoming bills · next 14 days") {
                ForEach(upcoming.prefix(8)) { item in
                    UpcomingRow(item: item)
                        .swipeActions {
                            if item.mode == .remind {
                                Button("Paid", systemImage: "checkmark") { markPaid(item) }
                                    .tint(.green)
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var goalsSection: some View {
        Section {
            if goals.isEmpty {
                Button { editing = .goal } label: { Label("Start a savings goal", systemImage: "target") }
            }
            ForEach(goals.filter { !$0.isArchived }) { goal in
                NavigationLink { GoalDetailView(goal: goal) } label: { GoalRow(goal: goal, currencyCode: settings.currencyCode) }
            }
        } header: {
            Text("Savings goals")
        }
    }

    // MARK: Actions

    private func refresh() {
        let calculator = settings.calculator
        do {
            let recurring = RecurringService(context: context, calculator: calculator)
            let budgets = BudgetService(context: context, calculator: calculator)
            statuses = try budgets.statuses()
            let cycle = calculator.cycle(containing: .now)
            safe = try budgets.safeToSpend(upcomingRecurringMinor: recurring.scheduledSpend(in: cycle, after: .now))
            upcoming = try recurring.upcoming(days: 14)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markPaid(_ item: UpcomingItem) {
        let recurring = RecurringService(context: context, calculator: settings.calculator)
        do {
            if let rule = try recurring.rules().first(where: { $0.id == item.ruleID }) {
                try recurring.markPaid(rule)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func money(_ minor: Int64) -> String {
        MoneyFormat.string(minor: minor, currencyCode: settings.currencyCode, showsFraction: false)
    }
}

// MARK: - Components

struct BudgetRing: View {
    let progress: Double
    let isOver: Bool

    var body: some View {
        ZStack {
            Circle().stroke(Color(.tertiarySystemFill), lineWidth: 10)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(isOver ? Color.red : progress >= 0.8 ? Color.orange : ChartColors.spend, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(progress.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption.bold().monospacedDigit())
        }
        .accessibilityLabel("Budget used")
        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
    }
}

struct BudgetRow: View {
    let status: BudgetStatus
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(status.emoji) \(status.name)")
                Spacer()
                Text(status.isOver
                     ? String(localized: "\(MoneyFormat.string(minor: -status.remainingMinor, currencyCode: currencyCode, showsFraction: false)) over")
                     : String(localized: "\(MoneyFormat.string(minor: status.remainingMinor, currencyCode: currencyCode, showsFraction: false)) left"))
                    .monospacedDigit()
                    .foregroundStyle(status.isOver ? .red : .secondary)
            }
            .font(.subheadline)
            ProgressView(value: min(status.progress, 1))
                .tint(status.isOver ? .red : status.progress >= 0.8 ? .orange : Color(hex: status.colorHex))
            Text("\(MoneyFormat.string(minor: status.spentMinor, currencyCode: currencyCode, showsFraction: false)) of \(MoneyFormat.string(minor: status.availableMinor, currencyCode: currencyCode, showsFraction: false))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

struct UpcomingRow: View {
    let item: UpcomingItem

    var body: some View {
        HStack(spacing: 12) {
            Text(item.emoji)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(dueText)
                    .font(.caption)
                    .foregroundStyle(item.date < Calendar.current.startOfDay(for: .now) ? .orange : .secondary)
            }
            Spacer()
            Text(MoneyFormat.string(minor: item.amountMinor * item.kind.cashFlowSign, currencyCode: item.currencyCode, sign: item.kind == .transfer ? .none : .explicit))
                .monospacedDigit()
                .foregroundStyle(item.kind == .income ? .green : .primary)
        }
        .accessibilityElement(children: .combine)
    }

    private var dueText: String {
        let calendar = Calendar.current
        let mode = item.mode == .autoPost ? String(localized: "auto") : String(localized: "reminder")
        if calendar.isDateInToday(item.date) { return String(localized: "Today · \(mode)") }
        if calendar.isDateInTomorrow(item.date) { return String(localized: "Tomorrow · \(mode)") }
        if item.date < .now { return String(localized: "Overdue since \(item.date.formatted(.dateTime.day().month())) · swipe to mark paid") }
        return "\(item.date.formatted(.dateTime.weekday().day().month())) · \(mode)"
    }
}

#Preview {
    BudgetsView()
        .previewEnvironment()
}
