import SwiftUI

@main
struct KnockApp: App {
    @State private var router = AppRouter.shared

    init() {
        LaunchTiming.markAppInit()
    }

    var body: some Scene {
        WindowGroup {
            SpikeView()
                .environment(router)
        }
    }
}
