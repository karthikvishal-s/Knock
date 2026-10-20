import Foundation
import KnockKit
import Observation

/// User preferences, persisted in the App Group's `UserDefaults` so intents and widgets see them.
@Observable
final class AppSettings {
    static let shared = AppSettings(defaults: StoreLocation.sharedDefaults)

    private enum Key {
        static let cycleStartDay = "settings.cycleStartDay"
        static let firstWeekday = "settings.firstWeekday"
        static let hapticsEnabled = "settings.hapticsEnabled"
        static let captureMode = "settings.captureMode"
        static let asksNote = "settings.asksNote"
        static let asksAccount = "settings.asksAccount"
        static let hidesTotals = "settings.hidesTotals"
        static let appLockEnabled = "settings.appLockEnabled"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        static let dailyReminderEnabled = "settings.dailyReminderEnabled"
        static let dailyReminderMinutes = "settings.dailyReminderMinutes"
        static let budgetAlertsEnabled = "settings.budgetAlertsEnabled"
        static let billRemindersEnabled = "settings.billRemindersEnabled"
    }

    enum CaptureMode: String, CaseIterable, Identifiable {
        /// Intents prompt in place without opening the app.
        case inPlace
        /// Intents open the app's quick-entry sheet.
        case sheet

        var id: String { rawValue }
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// v1 is single-currency (PLAN.md §2); every entry still stores its code.
    let currencyCode = "INR"

    /// 1...31. Months shorter than this start their cycle on their last day.
    var cycleStartDay: Int {
        didSet { defaults.set(cycleStartDay, forKey: Key.cycleStartDay) }
    }

    /// 0 follows the system; otherwise 1 = Sunday ... 7 = Saturday.
    var firstWeekday: Int {
        didSet { defaults.set(firstWeekday, forKey: Key.firstWeekday) }
    }

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) }
    }

    var captureMode: CaptureMode {
        didSet { defaults.set(captureMode.rawValue, forKey: Key.captureMode) }
    }

    /// Quick-log asks "Add a note?" after the category.
    var asksNote: Bool {
        didSet { defaults.set(asksNote, forKey: Key.asksNote) }
    }

    /// Quick-log asks which account, when there's more than one.
    var asksAccount: Bool {
        didSet { defaults.set(asksAccount, forKey: Key.asksAccount) }
    }

    /// With App Lock on, confirmations and widgets hide monthly totals.
    var hidesTotals: Bool {
        didSet { defaults.set(hidesTotals, forKey: Key.hidesTotals) }
    }

    var appLockEnabled: Bool {
        didSet { defaults.set(appLockEnabled, forKey: Key.appLockEnabled) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    var dailyReminderEnabled: Bool {
        didSet { defaults.set(dailyReminderEnabled, forKey: Key.dailyReminderEnabled) }
    }

    /// Minutes after midnight for the "log today's spending" reminder.
    var dailyReminderMinutes: Int {
        didSet { defaults.set(dailyReminderMinutes, forKey: Key.dailyReminderMinutes) }
    }

    var budgetAlertsEnabled: Bool {
        didSet { defaults.set(budgetAlertsEnabled, forKey: Key.budgetAlertsEnabled) }
    }

    var billRemindersEnabled: Bool {
        didSet { defaults.set(billRemindersEnabled, forKey: Key.billRemindersEnabled) }
    }

    /// Whether totals may be shown outside the locked app (confirmations, widgets).
    var showsTotalsOutsideApp: Bool { !(appLockEnabled && hidesTotals) }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.cycleStartDay: 1, Key.firstWeekday: 0, Key.hapticsEnabled: true,
            Key.captureMode: CaptureMode.inPlace.rawValue, Key.asksNote: false, Key.asksAccount: false,
            Key.hidesTotals: true, Key.appLockEnabled: false, Key.hasCompletedOnboarding: false,
            Key.dailyReminderEnabled: false, Key.dailyReminderMinutes: 21 * 60, Key.budgetAlertsEnabled: true,
            Key.billRemindersEnabled: true,
        ])
        cycleStartDay = defaults.integer(forKey: Key.cycleStartDay)
        firstWeekday = defaults.integer(forKey: Key.firstWeekday)
        hapticsEnabled = defaults.bool(forKey: Key.hapticsEnabled)
        captureMode = CaptureMode(rawValue: defaults.string(forKey: Key.captureMode) ?? "") ?? .inPlace
        asksNote = defaults.bool(forKey: Key.asksNote)
        asksAccount = defaults.bool(forKey: Key.asksAccount)
        hidesTotals = defaults.bool(forKey: Key.hidesTotals)
        appLockEnabled = defaults.bool(forKey: Key.appLockEnabled)
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        dailyReminderEnabled = defaults.bool(forKey: Key.dailyReminderEnabled)
        dailyReminderMinutes = defaults.integer(forKey: Key.dailyReminderMinutes)
        budgetAlertsEnabled = defaults.bool(forKey: Key.budgetAlertsEnabled)
        billRemindersEnabled = defaults.bool(forKey: Key.billRemindersEnabled)
    }

    var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        if (1...7).contains(firstWeekday) {
            calendar.firstWeekday = firstWeekday
        }
        return calendar
    }

    var calculator: PeriodCalculator {
        PeriodCalculator(calendar: calendar, cycleStartDay: cycleStartDay)
    }
}
