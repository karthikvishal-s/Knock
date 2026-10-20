import AppIntents
import KnockKit
import SwiftUI
import WidgetKit

// MARK: - Quick Log (small)

struct QuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickLog", provider: SnapshotProvider()) { entry in
            QuickLogView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Log")
        .description("Log an expense or income in one tap.")
        .supportedFamilies([.systemSmall])
    }
}

struct QuickLogView: View {
    let entry: SnapshotEntry

    var body: some View {
        VStack(spacing: 8) {
            Button(intent: OpenQuickEntryIntent(kind: .expense)) {
                Label("Expense", systemImage: "minus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .tint(.blue)
            Button(intent: OpenQuickEntryIntent(kind: .income)) {
                Label("Income", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .tint(.green)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 16))
    }
}

// MARK: - Summary (small / medium / large)

struct SummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Summary", provider: SnapshotProvider()) { entry in
            SummaryWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("This Month")
        .description("Spending, budget and what's safe to spend today.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct SummaryWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot? { entry.snapshot }

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemMedium: medium
        default: large
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("This month").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let progress = snapshot?.budgetProgress {
                    Gauge(value: min(progress, 1)) { EmptyView() }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .scaleEffect(0.55)
                        .frame(width: 26, height: 26)
                        .tint(progress > 1 ? .red : progress >= 0.8 ? .orange : .blue)
                }
            }
            Text(WidgetFormat.money(snapshot?.spentMinor, snapshot))
                .font(.title2.bold())
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .privacySensitive()
            Spacer(minLength: 0)
            if let perDay = entry.perDayMinor {
                Text("\(WidgetFormat.money(perDay, snapshot))/day safe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            } else if let snapshot {
                Text("Income \(WidgetFormat.money(snapshot.incomeMinor, snapshot))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Spent this month").font(.caption).foregroundStyle(.secondary)
                Text(WidgetFormat.money(snapshot?.spentMinor, snapshot))
                    .font(.title2.bold())
                    .monospacedDigit()
                    .privacySensitive()
                if let left = entry.leftTodayMinor {
                    Label("\(WidgetFormat.money(left, snapshot)) left today", systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(left < 0 ? .red : .secondary)
                        .privacySensitive()
                }
                Spacer(minLength: 0)
                Text("Income \(WidgetFormat.money(snapshot?.incomeMinor, snapshot))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            }
            VStack(spacing: 8) {
                Button(intent: OpenQuickEntryIntent(kind: .expense)) {
                    Image(systemName: "minus").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .tint(.blue)
                .accessibilityLabel("Log expense")
                Button(intent: OpenQuickEntryIntent(kind: .income)) {
                    Image(systemName: "plus").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .tint(.green)
                .accessibilityLabel("Log income")
            }
            .font(.title3.bold())
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .frame(width: 64)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            medium.frame(height: 120)
            Divider()
            if let categories = snapshot?.topCategories, !categories.isEmpty {
                ForEach(categories.prefix(3), id: \.name) { line in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("\(line.emoji) \(line.name)").font(.caption)
                            Spacer()
                            Text(WidgetFormat.money(line.spentMinor, snapshot)).font(.caption.monospacedDigit()).privacySensitive()
                        }
                        if let budget = line.budgetMinor, budget > 0 {
                            ProgressView(value: min(Double(line.spentMinor) / Double(budget), 1))
                                .tint(line.spentMinor > budget ? .red : Color(hex: line.colorHex))
                        }
                    }
                }
                Divider()
            }
            ForEach(Array((snapshot?.recent ?? []).prefix(3).enumerated()), id: \.offset) { _, line in
                HStack {
                    Text(line.emoji)
                    Text(line.title).font(.caption).lineLimit(1)
                    Spacer()
                    Text(WidgetFormat.money(line.signedMinor, snapshot, sign: line.kindRaw == "transfer" ? .none : .explicit))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(line.signedMinor > 0 && line.kindRaw != "transfer" ? .green : .primary)
                        .privacySensitive()
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Lock Screen

struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockScreen", provider: SnapshotProvider()) { entry in
            LockScreenView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Budget")
        .description("Budget used and what's safe to spend.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LockScreenView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let snapshot = entry.snapshot
        switch family {
        case .accessoryCircular:
            if let progress = snapshot?.budgetProgress {
                Gauge(value: min(progress, 1)) {
                    Image(systemName: "indianrupeesign")
                } currentValueLabel: {
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                }
                .gaugeStyle(.accessoryCircular)
                .widgetAccentable()
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "hand.tap.fill").font(.title2)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Spent \(WidgetFormat.money(snapshot?.spentMinor, snapshot))")
                    .font(.headline)
                    .widgetAccentable()
                    .privacySensitive()
                if let perDay = entry.perDayMinor {
                    Text("\(WidgetFormat.money(perDay, snapshot))/day · \(entry.daysRemaining ?? 0)d left")
                        .privacySensitive()
                } else {
                    Text("Income \(WidgetFormat.money(snapshot?.incomeMinor, snapshot))")
                        .privacySensitive()
                }
            }
        default:
            if let left = entry.leftTodayMinor {
                Text("\(WidgetFormat.money(left, snapshot)) safe today")
            } else {
                Text("\(WidgetFormat.money(snapshot?.spentMinor, snapshot)) spent")
            }
        }
    }
}

// MARK: - Control Center

struct LogExpenseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.karthikvishal.knock.control.expense") {
            ControlWidgetButton(action: OpenQuickEntryIntent(kind: .expense)) {
                Label("Log Expense", systemImage: "minus.circle")
            }
        }
        .displayName("Log Expense")
        .description("Opens Knock's keypad to log an expense.")
    }
}

struct LogIncomeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.karthikvishal.knock.control.income") {
            ControlWidgetButton(action: OpenQuickEntryIntent(kind: .income)) {
                Label("Log Income", systemImage: "plus.circle")
            }
        }
        .displayName("Log Income")
        .description("Opens Knock's keypad to log income.")
    }
}

extension Color {
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        let value = UInt32(digits, radix: 16) ?? 0x8E8E93
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

#Preview("Small", as: .systemSmall) {
    SummaryWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .placeholder)
}

#Preview("Medium", as: .systemMedium) {
    SummaryWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .placeholder)
}

#Preview("Large", as: .systemLarge) {
    SummaryWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .placeholder)
}

#Preview("Circular", as: .accessoryCircular) {
    LockScreenWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .placeholder)
}
