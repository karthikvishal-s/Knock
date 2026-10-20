import BackgroundTasks
import Foundation
import KnockKit
import SwiftData
import UserNotifications
import WidgetKit

/// Side effects of data changes, wherever they come from (app UI, intents, background):
/// budget alerts, recurring catch-up, reminder scheduling and widget refreshes.
@MainActor
final class AppCoordinator {
    static let shared = AppCoordinator()
    static let refreshTaskID = "com.karthikvishal.knock.refresh"

    private var observer: NSObjectProtocol?
    private var pending: Task<Void, Never>?

    private var context: ModelContext { AppBootstrap.container.mainContext }
    private var settings: AppSettings { .shared }

    /// Call once at launch. Intents launch the app process too, so this covers them.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: StoreEvents.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        BudgetSnapshotLine.provider = { [weak self] in self?.safeToSpendSentence() }
        postDueRecurring()
    }

    /// Foreground: catch up on recurring entries and re-plan notifications.
    func appBecameActive() {
        postDueRecurring()
        if !AppBootstrap.isUITesting {
            _ = try? AutoBackup.performIfNeeded(context: context)
        }
        Task { await NotificationScheduler.shared.reschedule(context: context, settings: settings) }
        WidgetSnapshotPublisher.publish(context: context, settings: settings)
    }

    func handleBackgroundRefresh() async {
        postDueRecurring()
        WidgetSnapshotPublisher.publish(context: context, settings: settings)
        scheduleBackgroundRefresh()
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Calendar.current.date(byAdding: .hour, value: 6, to: .now)
        Task { try? await BGTaskScheduler.shared.submitTaskRequest(request) }
    }

    /// Coalesces bursts of saves (e.g. an import) into one pass.
    private func scheduleRefresh() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            await self.evaluateBudgets()
            WidgetSnapshotPublisher.publish(context: self.context, settings: self.settings)
            await NotificationScheduler.shared.reschedule(context: self.context, settings: self.settings)
        }
    }

    private func postDueRecurring() {
        _ = try? RecurringService(context: context, calculator: settings.calculator).postDue()
    }

    private func evaluateBudgets() async {
        guard settings.budgetAlertsEnabled else { return }
        let calculator = settings.calculator
        guard let statuses = try? BudgetService(context: context, calculator: calculator).statuses() else { return }
        let cycle = calculator.cycle(containing: .now)
        let log = BudgetAlertLog()
        for status in statuses {
            let already = log.lastAlerted(budgetID: status.id, cycle: cycle)
            guard let threshold = BudgetMath.thresholdToAlert(thresholds: status.thresholds, progress: status.progress, alreadyAlerted: already) else { continue }
            log.record(threshold, budgetID: status.id, cycle: cycle)
            await NotificationScheduler.shared.sendBudgetAlert(status, threshold: threshold, currencyCode: settings.currencyCode,
                                                               showsAmounts: settings.showsTotalsOutsideApp)
        }
    }

    private func safeToSpendSentence() -> String? {
        let calculator = settings.calculator
        let cycle = calculator.cycle(containing: .now)
        let upcoming = (try? RecurringService(context: context, calculator: calculator).scheduledSpend(in: cycle, after: .now)) ?? 0
        guard let safe = try? BudgetService(context: context, calculator: calculator).safeToSpend(upcomingRecurringMinor: upcoming) else { return nil }
        let perDay = MoneyFormat.string(minor: safe.perDayMinor, currencyCode: settings.currencyCode, showsFraction: false)
        return String(localized: "You can spend about \(perDay) a day for the next \(safe.daysRemaining) days")
    }
}

/// Local notifications: the daily "log your spending" nudge, bill reminders and budget alerts.
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private let center = UNUserNotificationCenter.current()

    /// Asks for permission the first time any notification feature is turned on.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func reschedule(context: ModelContext, settings: AppSettings) async {
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let existing = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: existing.filter { $0.hasPrefix("bill-") || $0 == "daily-reminder" })

        if settings.dailyReminderEnabled {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Anything to log today?")
            content.body = String(localized: "Double-tap the back of your iPhone to add it in seconds.")
            var time = DateComponents()
            time.hour = settings.dailyReminderMinutes / 60
            time.minute = settings.dailyReminderMinutes % 60
            try? await center.add(UNNotificationRequest(identifier: "daily-reminder", content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: time, repeats: true)))
        }

        guard settings.billRemindersEnabled,
              let items = try? RecurringService(context: context, calculator: settings.calculator).upcoming(days: 30) else { return }
        // iOS keeps at most 64 pending requests; bills get up to 50 of them.
        for item in items.filter({ $0.mode == .remind && $0.date > .now }).prefix(50) {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(item.emoji) \(item.name) is due today")
            content.body = settings.showsTotalsOutsideApp
                ? MoneyFormat.string(minor: item.amountMinor, currencyCode: item.currencyCode) + " · " + String(localized: "Open Knock to mark it paid.")
                : String(localized: "Open Knock to mark it paid.")
            let components = settings.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            try? await center.add(UNNotificationRequest(identifier: "bill-\(item.id)", content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }
    }

    func sendBudgetAlert(_ status: BudgetStatus, threshold: Int, currencyCode: String, showsAmounts: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = threshold >= 100
            ? String(localized: "\(status.emoji) \(status.name): budget reached")
            : String(localized: "\(status.emoji) \(status.name): \(threshold)% used")
        if showsAmounts {
            let remaining = MoneyFormat.string(minor: max(status.remainingMinor, 0), currencyCode: currencyCode, showsFraction: false)
            content.body = status.isOver
                ? String(localized: "You're \(MoneyFormat.string(minor: -status.remainingMinor, currencyCode: currencyCode, showsFraction: false)) over this cycle.")
                : String(localized: "\(remaining) left this cycle.")
        }
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "budget-\(status.id)-\(threshold)", content: content, trigger: nil))
    }
}

/// Writes the widget snapshot to the App Group and reloads widgets and controls.
enum WidgetSnapshotPublisher {
    @MainActor
    static func publish(context: ModelContext, settings: AppSettings) {
        guard !AppBootstrap.isUITesting else { return }
        do {
            let snapshot = try WidgetSnapshotBuilder.build(context: context, calculator: settings.calculator,
                                                           currencyCode: settings.currencyCode, showsAmounts: settings.showsTotalsOutsideApp)
            try WidgetSnapshotStore.write(snapshot)
        } catch {
            // Widgets keep showing the previous snapshot; nothing for the user to act on.
        }
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }
}
