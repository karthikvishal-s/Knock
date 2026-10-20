import AppIntents
import KnockKit
import SwiftUI
import WidgetKit

@main
struct KnockWidgetsBundle: WidgetBundle {
    var body: some Widget {
        QuickLogWidget()
        SummaryWidget()
        LockScreenWidget()
        LogExpenseControl()
        LogIncomeControl()
    }
}

/// Pulls in `OpenQuickEntryIntent` from KnockKit for widget buttons and controls.
struct KnockWidgetIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [KnockKitIntents.self] }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// Set on the midnight entry: today's spending resets, so "left today" = tomorrow's per-day.
    var isNewDay = false

    var leftTodayMinor: Int64? {
        isNewDay ? snapshot?.tomorrowPerDayMinor : snapshot?.leftTodayMinor
    }

    var perDayMinor: Int64? {
        isNewDay ? snapshot?.tomorrowPerDayMinor : snapshot?.perDayMinor
    }

    var daysRemaining: Int? {
        isNewDay ? snapshot?.daysRemaining.map { max($0 - 1, 1) } : snapshot?.daysRemaining
    }
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .placeholder : WidgetSnapshotStore.read() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.read()
        var entries = [SnapshotEntry(date: .now, snapshot: snapshot)]
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now)
        // A new day resets "left today"; a new cycle needs the app to recompute, so stop there.
        if let snapshot, midnight < snapshot.cycleEnd {
            entries.append(SnapshotEntry(date: midnight, snapshot: snapshot, isNewDay: true))
        }
        let next = calendar.date(byAdding: .hour, value: 1, to: midnight) ?? midnight
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

// MARK: - Formatting

enum WidgetFormat {
    static func money(_ minor: Int64?, _ snapshot: WidgetSnapshot?, sign: MoneyFormat.Sign = .none) -> String {
        guard let minor, let snapshot else { return "—" }
        guard snapshot.showsAmounts else { return "•••" }
        return MoneyFormat.string(minor: minor, currencyCode: snapshot.currencyCode, sign: sign, showsFraction: false)
    }
}
