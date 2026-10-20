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

    init(defaults: UserDefaults) {
        self.defaults = defaults
        defaults.register(defaults: [Key.cycleStartDay: 1, Key.firstWeekday: 0, Key.hapticsEnabled: true])
        cycleStartDay = defaults.integer(forKey: Key.cycleStartDay)
        firstWeekday = defaults.integer(forKey: Key.firstWeekday)
        hapticsEnabled = defaults.bool(forKey: Key.hapticsEnabled)
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
