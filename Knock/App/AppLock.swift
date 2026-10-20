import LocalAuthentication
import Observation
import SwiftUI

/// Face ID / passcode lock. Locks when the app goes to the background; Back Tap and Siri
/// logging keep working because they never show the app's UI.
@Observable
final class AppLock {
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    var lastError: String?

    init(settings: AppSettings) {
        isLocked = settings.appLockEnabled && !AppBootstrap.isUITesting
    }

    func lockIfEnabled(_ settings: AppSettings) {
        if settings.appLockEnabled, !AppBootstrap.isUITesting { isLocked = true }
    }

    /// Face ID with passcode fallback.
    func unlock(reason: String = String(localized: "Unlock Knock")) async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        do {
            if try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) {
                isLocked = false
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Confirms the device can authenticate before App Lock is switched on.
    static func confirmAvailable() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Turn on App Lock"))) ?? false
    }

    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return String(localized: "Passcode")
        }
    }
}

/// Covers the app while locked, and blurs it in the app switcher when App Lock is on.
struct LockGate: ViewModifier {
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    let lock: AppLock

    func body(content: Content) -> some View {
        content
            .overlay {
                if lock.isLocked || (settings.appLockEnabled && scenePhase != .active && !AppBootstrap.isUITesting) {
                    ZStack {
                        Rectangle().fill(.regularMaterial).ignoresSafeArea()
                        if lock.isLocked {
                            VStack(spacing: 16) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.tint)
                                Text("Knock is locked")
                                    .font(.title2.bold())
                                Button("Unlock with \(AppLock.biometryName)") {
                                    Task { await lock.unlock() }
                                }
                                .buttonStyle(.glassProminent)
                                if let error = lock.lastError {
                                    Text(error).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { lock.lockIfEnabled(settings) }
                if phase == .active, lock.isLocked { Task { await lock.unlock() } }
            }
            .task { if lock.isLocked { await lock.unlock() } }
    }
}
