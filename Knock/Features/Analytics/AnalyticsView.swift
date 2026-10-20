import Charts
import KnockKit
import SwiftData
import SwiftUI

struct AnalyticsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var model = AnalyticsModel()
    @State private var editsCustomRange = false
    @State private var selectedDay: Date?
    @State private var version = StoreEvents.dataVersion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    periodHeader
                    if let report = model.report {
                        content(report)
                    } else if model.isLoading {
                        ProgressView().padding(.top, 60)
                    }
                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Analytics")
            .task(id: LoadKey(period: model.period, version: version, cycle: settings.cycleStartDay, weekday: settings.firstWeekday)) {
                await model.load(settings: settings)
            }
            .onChange(of: settings.cycleStartDay) { model.reset(to: model.kind, settings: settings) }
            .onReceive(NotificationCenter.default.publisher(for: StoreEvents.didChange)) { _ in version = StoreEvents.dataVersion }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in version = StoreEvents.dataVersion }
            .sheet(isPresented: $editsCustomRange) { customRangeSheet }
            .sheet(item: $selectedDay) { day in
                DayDetailView(day: day)
            }
        }
    }

    private struct LoadKey: Equatable {
        let period: Period?
        let version: Int
        let cycle: Int
        let weekday: Int
    }

    // MARK: Header

    private var periodHeader: some View {
        VStack(spacing: 10) {
            Picker("Period", selection: Binding(get: { model.kind }, set: { kind in
                if kind == .custom { editsCustomRange = true }
                model.reset(to: kind, settings: settings)
            })) {
                Text("Week").tag(Period.Kind.week)
                Text("Month").tag(Period.Kind.cycle)
                Text("Year").tag(Period.Kind.year)
                Text("Custom").tag(Period.Kind.custom)
            }
            .pickerStyle(.segmented)

            HStack {
                Button("Previous", systemImage: "chevron.left") { model.shift(-1, settings: settings) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                Spacer()
                Button {
                    if model.kind == .custom { editsCustomRange = true }
                } label: {
                    Text(model.title(settings: settings))
                        .font(.headline)
                        .monospacedDigit()
                }
                .buttonStyle(.plain)
                .disabled(model.kind != .custom)
                Spacer()
                Button("Next", systemImage: "chevron.right") { model.shift(1, settings: settings) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .disabled(model.period?.contains(.now) == true || (model.period?.start ?? .distantFuture) > .now)
            }
        }
        .padding(.top, 8)
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }
            if value.translation.width < 0, model.period?.contains(.now) != true {
                model.shift(1, settings: settings)
            } else if value.translation.width > 0 {
                model.shift(-1, settings: settings)
            }
        })
    }

    private var customRangeSheet: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $model.customRange.from, displayedComponents: .date)
                DatePicker("Through", selection: $model.customRange.through, in: model.customRange.from..., displayedComponents: .date)
            }
            .navigationTitle("Custom range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Apply", role: .confirm) {
                    model.reset(to: .custom, settings: settings)
                    editsCustomRange = false
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ report: AnalyticsReport) -> some View {
        let code = settings.currencyCode
        SummaryGrid(totals: report.totals, currencyCode: code)

        if report.totals.count == 0 {
            ContentUnavailableView("Nothing logged in this period", systemImage: "chart.bar", description: Text("Swipe to another period or log something new."))
                .padding(.top, 20)
        } else {
            InsightsCard(insights: report.insights, period: report.period, currencyCode: code)

            CategoryBreakdownCard(title: "Spending by category", slices: report.spendingByCategory, total: report.totals.netSpendMinor,
                                  currencyCode: code, period: report.period)
            if !report.incomeByCategory.isEmpty {
                CategoryBreakdownCard(title: "Income by category", slices: report.incomeByCategory, total: report.totals.incomeMinor,
                                      currencyCode: code, period: report.period)
            }

            if report.granularity == .month {
                YearBarsCard(buckets: report.buckets, currencyCode: code) { monthStart in
                    model.show(settings.calculator.cycle(containing: monthStart.addingTimeInterval(86_400 * Double(max(settings.cycleStartDay - 1, 0)))))
                }
            } else {
                TrendCard(series: report.dailySpend, averageMinor: report.insights.dailyAverageMinor, currencyCode: code)
            }
            IncomeVsExpenseCard(buckets: report.buckets, granularity: report.granularity, currencyCode: code)
            CashFlowCard(series: report.cumulativeNet.filter { $0.date <= .now }, currencyCode: code)
            if report.granularity == .day {
                HeatmapCard(series: report.dailySpend, calendar: settings.calendar) { selectedDay = $0 }
            }
            NetWorthCard(series: report.netWorth.filter { $0.date <= .now }, currencyCode: code)
            BudgetPerformanceSection(period: report.period, spending: report.spendingByCategory)
            if !report.topPayees.isEmpty {
                RankedCard(title: "Top payees", items: report.topPayees, currencyCode: code)
            }
            if !report.topTags.isEmpty {
                RankedCard(title: "Top tags", items: report.topTags.map { RankedItem(name: "#" + $0.name, amountMinor: $0.amountMinor, count: $0.count) }, currencyCode: code)
            }
        }
    }
}

extension Date: @retroactive Identifiable {
    public var id: TimeInterval { timeIntervalSinceReferenceDate }
}

/// Budget vs actual per category for the current cycle, over-budget bars in red.
struct BudgetPerformanceSection: View {
    let period: Period
    let spending: [CategorySlice]

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let statuses = period.kind == .cycle && period.contains(.now)
            ? ((try? BudgetService(context: context, calculator: settings.calculator).statuses()) ?? []).filter { $0.categoryID != nil }
            : []
        if !statuses.isEmpty {
            ChartCard(title: "Budget vs actual") {
                Chart(statuses) { status in
                    BarMark(x: .value("Budget", status.availableMinor.rupees), y: .value("Category", status.name))
                        .foregroundStyle(Color(.tertiarySystemFill))
                        .cornerRadius(4)
                    BarMark(x: .value("Spent", max(status.spentMinor, 0).rupees), y: .value("Category", status.name))
                        .foregroundStyle(status.isOver ? Color.red : ChartColors.spend)
                        .cornerRadius(4)
                        .annotation(position: .trailing) {
                            Text(status.progress.formatted(.percent.precision(.fractionLength(0))))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(status.isOver ? .red : .secondary)
                        }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel { if let v = value.as(Double.self) { Text(compactMoney(Int64(v * 100), currencyCode: settings.currencyCode)) } }
                    }
                }
                .frame(height: CGFloat(statuses.count) * 36 + 30)
            }
        }
    }
}

#Preview {
    AnalyticsView()
        .previewEnvironment()
}
