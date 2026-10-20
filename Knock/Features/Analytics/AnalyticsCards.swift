import Charts
import KnockKit
import SwiftData
import SwiftUI

// MARK: - Summary & insights

struct SummaryGrid: View {
    let totals: Totals
    let currencyCode: String

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                SummaryCard(title: "Income", minor: totals.incomeMinor, currencyCode: currencyCode, color: .primary)
                SummaryCard(title: "Spent", minor: totals.netSpendMinor, currencyCode: currencyCode, color: .primary)
            }
            GridRow {
                SummaryCard(title: "Net", minor: totals.netMinor, currencyCode: currencyCode, color: totals.netMinor < 0 ? .red : .primary, signed: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Savings rate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(totals.savingsRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—")
                        .font(.headline)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct InsightsCard: View {
    let insights: Insights
    let period: Period
    let currencyCode: String

    var body: some View {
        ChartCard(title: "Insights") {
            VStack(alignment: .leading, spacing: 10) {
                row("calendar", "Daily average", money(insights.dailyAverageMinor))
                if let projected = insights.projectedSpendMinor {
                    row("chart.line.uptrend.xyaxis", "Projected by period end", money(projected))
                }
                if let delta = insights.comparisonDeltaMinor {
                    let ratio = insights.comparisonRatio.map { " (\($0 >= 0 ? "+" : "")\($0.formatted(.percent.precision(.fractionLength(0)))))" } ?? ""
                    row(delta > 0 ? "arrow.up.right" : "arrow.down.right",
                        "vs same days last period",
                        MoneyFormat.string(minor: delta, currencyCode: currencyCode, sign: .explicit, showsFraction: false) + ratio)
                }
                if let biggest = insights.biggestExpense {
                    row("flame", "Biggest expense", "\(money(biggest.amountMinor)) · \(biggest.label)")
                }
                if let frequent = insights.mostFrequentCategory {
                    row("repeat", "Most frequent", "\(frequent.name) × \(frequent.count)")
                }
                row("leaf", "No-spend days", "\(insights.noSpendDays)")
            }
        }
    }

    private func money(_ minor: Int64) -> String {
        MoneyFormat.string(minor: minor, currencyCode: currencyCode, showsFraction: false)
    }

    private func row(_ symbol: String, _ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: symbol)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Categories

struct CategoryBreakdownCard: View {
    let title: LocalizedStringKey
    let slices: [CategorySlice]
    let total: Int64
    let currencyCode: String
    let period: Period

    @State private var selectedAngle: Double?

    /// Top six plus "Other" — more slices than that can't be told apart.
    private var chartSlices: [CategorySlice] {
        guard slices.count > 7 else { return slices }
        let rest = slices.dropFirst(6)
        let restTotal = rest.reduce(0) { $0 + $1.amountMinor }
        let other = CategorySlice(id: nil, name: String(localized: "Other"), emoji: "⋯", colorHex: "", amountMinor: restTotal,
                                  count: rest.reduce(0) { $0 + $1.count }, share: rest.reduce(0) { $0 + $1.share })
        return Array(slices.prefix(6)) + [other]
    }

    private var selected: CategorySlice? {
        guard let selectedAngle else { return nil }
        var running = 0.0
        return chartSlices.first { slice in
            running += slice.amountMinor.rupees
            return selectedAngle <= running
        }
    }

    var body: some View {
        ChartCard(title: title) {
            if slices.isEmpty {
                Text("Nothing here for this period.").foregroundStyle(.secondary)
            } else {
                Chart(chartSlices) { slice in
                    SectorMark(angle: .value("Amount", slice.amountMinor.rupees), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .cornerRadius(4)
                        .foregroundStyle(color(slice))
                        .opacity(selected == nil || selected?.name == slice.name ? 1 : 0.4)
                        .accessibilityLabel(slice.name)
                        .accessibilityValue("\(MoneyFormat.string(minor: slice.amountMinor, currencyCode: currencyCode)), \(slice.share.formatted(.percent.precision(.fractionLength(0))))")
                }
                .chartAngleSelection(value: $selectedAngle)
                .chartBackground { proxy in
                    GeometryReader { geometry in
                        if let frame = proxy.plotFrame {
                            let rect = geometry[frame]
                            VStack(spacing: 2) {
                                Text(selected?.name ?? String(localized: "Total"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(MoneyFormat.string(minor: selected?.amountMinor ?? total, currencyCode: currencyCode, showsFraction: false))
                                    .font(.title3.bold())
                                    .monospacedDigit()
                            }
                            .position(x: rect.midX, y: rect.midY)
                        }
                    }
                }
                .frame(height: 220)

                VStack(spacing: 0) {
                    ForEach(slices) { slice in
                        NavigationLink {
                            CategoryDrilldownView(slice: slice, period: period)
                        } label: {
                            HStack(spacing: 10) {
                                Circle().fill(Color(hex: slice.colorHex)).frame(width: 10, height: 10)
                                Text("\(slice.emoji) \(slice.name)")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(slice.share.formatted(.percent.precision(.fractionLength(0))))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Text(MoneyFormat.string(minor: slice.amountMinor, currencyCode: currencyCode, showsFraction: false))
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                                    .frame(minWidth: 80, alignment: .trailing)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.subheadline)
                            .padding(.vertical, 8)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func color(_ slice: CategorySlice) -> Color {
        slice.colorHex.isEmpty ? ChartColors.other : Color(hex: slice.colorHex)
    }
}

/// One category's transactions in the period, with a daily bar chart.
struct CategoryDrilldownView: View {
    let slice: CategorySlice
    let period: Period

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var editing: LedgerEntry?

    var body: some View {
        List {
            Section {
                Chart(entries) { entry in
                    BarMark(x: .value("Day", entry.date, unit: period.kind == .year ? .month : .day),
                            y: .value("Amount", (entry.kind == .refund ? -entry.amountMinor : entry.amountMinor).rupees))
                        .foregroundStyle(Color(hex: slice.colorHex.isEmpty ? "#8E8E93" : slice.colorHex))
                        .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel { if let v = value.as(Double.self) { Text(compactMoney(Int64(v * 100), currencyCode: settings.currencyCode)) } }
                    }
                }
                .frame(height: 160)
                .listRowBackground(Color.clear)
            }
            Section("\(entries.count) transactions · \(MoneyFormat.string(minor: slice.amountMinor, currencyCode: settings.currencyCode))") {
                ForEach(entries) { entry in
                    Button { editing = entry } label: { EntryRow(entry: entry) }
                        .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("\(slice.emoji) \(slice.name)")
        .sheet(item: $editing) { TransactionEditor(entry: $0) }
    }

    private var entries: [LedgerEntry] {
        let start = period.start, end = period.end
        let all = (try? context.fetch(FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.date >= start && $0.date < end },
                                                                    sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        return all.filter { entry in
            guard entry.kind != .transfer else { return false }
            let id = entry.category?.id
            return id == slice.id || (entry.category?.parent?.id != nil && entry.category?.parent?.id == slice.id)
        }
    }
}

// MARK: - Time series

struct TrendCard: View {
    let series: [SeriesPoint]
    let averageMinor: Int64
    let currencyCode: String
    @State private var selection: Date?

    private var selected: SeriesPoint? {
        guard let selection else { return nil }
        return series.first { Calendar.current.isDate($0.date, inSameDayAs: selection) }
    }

    var body: some View {
        ChartCard(title: "Daily spending", subtitle: selected.map { "\($0.date.formatted(.dateTime.day().month())) · \(MoneyFormat.string(minor: $0.valueMinor, currencyCode: currencyCode, showsFraction: false))" }
                  ?? String(localized: "Average \(MoneyFormat.string(minor: averageMinor, currencyCode: currencyCode, showsFraction: false)) a day")) {
            Chart {
                ForEach(series) { point in
                    BarMark(x: .value("Day", point.date, unit: .day), y: .value("Spent", max(point.valueMinor, 0).rupees))
                        .foregroundStyle(ChartColors.spend.opacity(selected == nil || selected?.date == point.date ? 1 : 0.4))
                        .cornerRadius(4)
                }
                if averageMinor > 0 {
                    RuleMark(y: .value("Average", averageMinor.rupees))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .leading) {
                            Text("avg").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartXSelection(value: $selection)
            .moneyYAxis(currencyCode)
            .frame(height: 180)
            .accessibilityChartDescriptor(SeriesChartDescriptor(title: String(localized: "Daily spending"), points: series.map { ($0.date, $0.valueMinor.rupees) },
                                                                valueTitle: String(localized: "Spent"), dateStyle: .dateTime.day().month()))
        }
    }
}

struct YearBarsCard: View {
    let buckets: [Bucket]
    let currencyCode: String
    var onSelectMonth: (Date) -> Void
    @State private var selection: Date?

    var body: some View {
        ChartCard(title: "Spending by month", subtitle: String(localized: "Tap a month to open it")) {
            Chart(buckets) { bucket in
                BarMark(x: .value("Month", bucket.start, unit: .month), y: .value("Spent", max(bucket.spendMinor, 0).rupees))
                    .foregroundStyle(ChartColors.spend)
                    .cornerRadius(4)
            }
            .chartXSelection(value: $selection)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
            .moneyYAxis(currencyCode)
            .frame(height: 180)
            .onChange(of: selection) { _, date in
                if let date, let bucket = buckets.last(where: { $0.start <= date }) {
                    onSelectMonth(bucket.start)
                }
            }
            .accessibilityChartDescriptor(SeriesChartDescriptor(title: String(localized: "Spending by month"), points: buckets.map { ($0.start, $0.spendMinor.rupees) },
                                                                valueTitle: String(localized: "Spent"), dateStyle: .dateTime.month(.wide)))
        }
    }
}

struct IncomeVsExpenseCard: View {
    let buckets: [Bucket]
    let granularity: AnalyticsReport.Granularity
    let currencyCode: String

    private var unit: Calendar.Component { granularity == .month ? .month : .day }

    /// For day-level periods longer than two weeks, group into weeks so bars stay readable.
    private var shown: [Bucket] {
        guard granularity == .day, buckets.count > 14 else { return buckets }
        let calendar = Calendar.current
        var weeks: [Date: Bucket] = [:]
        for bucket in buckets {
            let start = calendar.dateInterval(of: .weekOfYear, for: bucket.start)?.start ?? bucket.start
            weeks[start, default: Bucket(start: start, incomeMinor: 0, spendMinor: 0)].incomeMinor += bucket.incomeMinor
            weeks[start, default: Bucket(start: start, incomeMinor: 0, spendMinor: 0)].spendMinor += bucket.spendMinor
        }
        return weeks.values.sorted { $0.start < $1.start }
    }

    private var shownUnit: Calendar.Component { granularity == .day && buckets.count > 14 ? .weekOfYear : unit }

    var body: some View {
        ChartCard(title: "Income vs spending") {
            Chart(shown) { bucket in
                BarMark(x: .value("Period", bucket.start, unit: shownUnit), y: .value("Amount", bucket.incomeMinor.rupees))
                    .foregroundStyle(by: .value("Series", String(localized: "Income")))
                    .position(by: .value("Series", String(localized: "Income")))
                    .cornerRadius(4)
                BarMark(x: .value("Period", bucket.start, unit: shownUnit), y: .value("Amount", max(bucket.spendMinor, 0).rupees))
                    .foregroundStyle(by: .value("Series", String(localized: "Spending")))
                    .position(by: .value("Series", String(localized: "Spending")))
                    .cornerRadius(4)
            }
            .chartForegroundStyleScale([String(localized: "Income"): ChartColors.income, String(localized: "Spending"): ChartColors.spend])
            .chartLegend(position: .top, alignment: .leading)
            .moneyYAxis(currencyCode)
            .frame(height: 200)
        }
    }
}

struct CashFlowCard: View {
    let series: [SeriesPoint]
    let currencyCode: String
    @State private var selection: Date?

    private var selected: SeriesPoint? {
        guard let selection else { return nil }
        return series.last { $0.date <= selection }
    }

    var body: some View {
        ChartCard(title: "Cash flow", subtitle: selected.map { "\($0.date.formatted(.dateTime.day().month())) · \(MoneyFormat.string(minor: $0.valueMinor, currencyCode: currencyCode, sign: .explicit, showsFraction: false))" }
                  ?? String(localized: "Cumulative income minus spending")) {
            Chart {
                RuleMark(y: .value("Zero", 0)).foregroundStyle(.quaternary)
                ForEach(series) { point in
                    AreaMark(x: .value("Day", point.date, unit: .day), y: .value("Net", point.valueMinor.rupees))
                        .foregroundStyle(ChartColors.income.opacity(0.15))
                    LineMark(x: .value("Day", point.date, unit: .day), y: .value("Net", point.valueMinor.rupees))
                        .foregroundStyle(ChartColors.income)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if let selected {
                    RuleMark(x: .value("Selected", selected.date, unit: .day)).foregroundStyle(.secondary.opacity(0.5))
                    PointMark(x: .value("Day", selected.date, unit: .day), y: .value("Net", selected.valueMinor.rupees))
                        .symbolSize(64)
                        .foregroundStyle(ChartColors.income)
                }
            }
            .chartXSelection(value: $selection)
            .moneyYAxis(currencyCode)
            .frame(height: 180)
            .accessibilityChartDescriptor(SeriesChartDescriptor(title: String(localized: "Cash flow"), points: series.map { ($0.date, $0.valueMinor.rupees) },
                                                                valueTitle: String(localized: "Net"), dateStyle: .dateTime.day().month()))
        }
    }
}

struct NetWorthCard: View {
    let series: [SeriesPoint]
    let currencyCode: String

    private var sampled: [SeriesPoint] {
        guard series.count > 120 else { return series }
        return series.enumerated().filter { $0.offset % 7 == 0 || $0.offset == series.count - 1 }.map(\.element)
    }

    var body: some View {
        ChartCard(title: "Net worth", subtitle: series.last.map { MoneyFormat.string(minor: $0.valueMinor, currencyCode: currencyCode, showsFraction: false) }) {
            Chart(sampled) { point in
                LineMark(x: .value("Day", point.date, unit: .day), y: .value("Net worth", point.valueMinor.rupees))
                    .foregroundStyle(ChartColors.spend)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .moneyYAxis(currencyCode)
            .frame(height: 150)
            .accessibilityChartDescriptor(SeriesChartDescriptor(title: String(localized: "Net worth"), points: sampled.map { ($0.date, $0.valueMinor.rupees) },
                                                                valueTitle: String(localized: "Net worth"), dateStyle: .dateTime.day().month()))
        }
    }
}

// MARK: - Heatmap

struct HeatmapCard: View {
    let series: [SeriesPoint]
    let calendar: Calendar
    var onSelect: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    /// Five-step scale by quantile of non-zero spend days.
    private func level(_ value: Int64) -> Int {
        guard value > 0 else { return 0 }
        let positive = series.map(\.valueMinor).filter { $0 > 0 }.sorted()
        guard let max = positive.last, max > 0 else { return 0 }
        let rank = Double(positive.firstIndex(of: value) ?? 0) / Double(Swift.max(positive.count - 1, 1))
        return Swift.min(4, 1 + Int(rank * 3.999))
    }

    private var leadingBlanks: Int {
        guard let first = series.first else { return 0 }
        return (calendar.component(.weekday, from: first.date) - calendar.firstWeekday + 7) % 7
    }

    var body: some View {
        ChartCard(title: "Spending calendar", subtitle: String(localized: "Darker = more spent. Tap a day.")) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 34) }
                ForEach(series) { point in
                    Button { onSelect(point.date) } label: {
                        Text(point.date, format: .dateTime.day())
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(level(point.valueMinor) >= 3 ? .white : .primary)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(ChartColors.heat(level(point.valueMinor)), in: .rect(cornerRadius: 6))
                            .opacity(point.date > .now ? 0.35 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(point.date > .now)
                    .accessibilityLabel("\(point.date.formatted(date: .abbreviated, time: .omitted)), \(MoneyFormat.string(minor: point.valueMinor, currencyCode: "INR"))")
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }
}

struct DayDetailView: View {
    let day: Date
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var editing: LedgerEntry?

    var body: some View {
        NavigationStack {
            List {
                let entries = self.entries
                if entries.isEmpty {
                    ContentUnavailableView("No transactions", systemImage: "leaf", description: Text("A no-spend day."))
                }
                ForEach(entries) { entry in
                    Button { editing = entry } label: { EntryRow(entry: entry) }
                        .buttonStyle(.plain)
                }
            }
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .sheet(item: $editing) { TransactionEditor(entry: $0) }
        }
        .presentationDetents([.medium, .large])
    }

    private var entries: [LedgerEntry] {
        let key = settings.calculator.dayKey(for: day)
        return (try? context.fetch(FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.dayKey == key }, sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }
}

// MARK: - Rankings

struct RankedCard: View {
    let title: LocalizedStringKey
    let items: [RankedItem]
    let currencyCode: String

    var body: some View {
        ChartCard(title: title) {
            let maxAmount = Double(items.map(\.amountMinor).max() ?? 1)
            VStack(spacing: 10) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text("\(item.count)×").foregroundStyle(.secondary)
                            Text(MoneyFormat.string(minor: item.amountMinor, currencyCode: currencyCode, showsFraction: false))
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                        GeometryReader { geometry in
                            Capsule()
                                .fill(ChartColors.spend)
                                .frame(width: max(4, geometry.size.width * Double(item.amountMinor) / maxAmount), height: 4)
                        }
                        .frame(height: 4)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - Axis helper

extension View {
    func moneyYAxis(_ currencyCode: String) -> some View {
        chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(compactMoney(Int64((v * 100).rounded()), currencyCode: currencyCode))
                    }
                }
            }
        }
    }
}
