import Foundation

/// Measures how long the process takes from `App.init` to the first intent `perform()`,
/// which is the cold-start cost Back Tap pays when the app isn't running.
enum LaunchTiming {
    private(set) static var appInitUptime: TimeInterval?

    static func markAppInit() {
        appInitUptime = ProcessInfo.processInfo.systemUptime
    }

    /// Milliseconds since the process first ran `App.init`, if it has.
    static func millisecondsSinceInit() -> Int? {
        guard let start = appInitUptime else { return nil }
        return Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
    }
}
