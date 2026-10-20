import AppIntents
import KnockKit
import SwiftData
import SwiftUI

/// Five-step guide: what Back Tap does → create the shortcut → assign it → try it → done.
/// Apps can't open the Back Tap setting directly, so the steps are illustrated (PLAN.md §3.7).
struct BackTapGuide: View {
    var onFinish: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var page = 0
    @State private var startedAt = Date.now
    @State private var detectedEntry: LedgerEntry?

    private let pageCount = 5

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    introPage.tag(0)
                    shortcutPage.tag(1)
                    settingsPage.tag(2)
                    tryPage.tag(3)
                    donePage.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button(action: advance) {
                    Text(page == pageCount - 1 ? "Done" : page == 0 ? "Set it up" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.glassProminent)
                .padding()
                .accessibilityIdentifier("guide-next")
            }
            .navigationTitle("Set up Back Tap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Skip") { onFinish() }
                    .accessibilityIdentifier("guide-skip")
            }
            .onReceive(NotificationCenter.default.publisher(for: StoreEvents.didChange)) { _ in checkForTestEntry() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in checkForTestEntry() }
        }
    }

    private func advance() {
        if page < pageCount - 1 {
            withAnimation { page += 1 }
            if page == 3 { startedAt = .now }
        } else {
            onFinish()
        }
    }

    // MARK: Pages

    private var introPage: some View {
        GuidePage(symbol: "hand.tap.fill", title: "Log in two taps on the back of your iPhone") {
            Text("Double-tap the back of your phone, type the amount, pick a category. Knock never has to open.")
            StepRow(number: "2×", text: "Double tap → **Log Expense**")
            StepRow(number: "3×", text: "Triple tap → **Log Income**")
            Text("Setup takes about a minute. You'll do it once.")
                .foregroundStyle(.secondary)
        }
    }

    private var shortcutPage: some View {
        GuidePage(symbol: "square.stack.3d.up.fill", title: "Create the shortcut") {
            Text("Back Tap can only run shortcuts saved in your Shortcuts library.")
                .foregroundStyle(.secondary)
            StepRow(number: "1", text: "Open the **Shortcuts** app and tap **＋**.")
            StepRow(number: "2", text: "Tap **Add Action**, search **Knock** and choose **Log Expense**.")
            StepRow(number: "3", text: "Tap the name at the top, rename it **Log Expense**, then **Done**.")
            StepRow(number: "4", text: "Repeat with **Log Income** for triple tap.")
            Button("Open Shortcuts", systemImage: "arrow.up.forward.app") {
                if let url = URL(string: "shortcuts://create-shortcut") { openURL(url) }
            }
            .buttonStyle(.glass)
            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
        }
    }

    private var settingsPage: some View {
        GuidePage(symbol: "gearshape.fill", title: "Assign it to Back Tap") {
            StepRow(number: "1", text: "Open **Settings** → **Accessibility** → **Touch**.")
            StepRow(number: "2", text: "Scroll down to **Back Tap** → **Double Tap**.")
            StepRow(number: "3", text: "Scroll to **Shortcuts** and pick **Log Expense**.")
            StepRow(number: "4", text: "Go back → **Triple Tap** → **Log Income**.")
            Button("Open Settings", systemImage: "gear") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.glass)
            Text("Settings opens on Knock's page — go back to the main list, then Accessibility.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var tryPage: some View {
        GuidePage(symbol: detectedEntry == nil ? "iphone.gen3.radiowaves.left.and.right" : "checkmark.seal.fill",
                  title: detectedEntry == nil ? "Try it now" : "Back Tap works") {
            if let entry = detectedEntry {
                Text("Logged \(MoneyFormat.string(minor: entry.amountMinor, currencyCode: entry.currencyCode)). You're all set.")
                Button("Delete the test entry", systemImage: "trash", role: .destructive) {
                    _ = try? TransactionService(context: context).delete(entry)
                    detectedEntry = nil
                }
                .buttonStyle(.glass)
            } else {
                Text("Double-tap the back of your iPhone and log a small test amount. This page will tick when it arrives.")
                ProgressView()
                    .padding(.top)
            }
        }
        .animation(.snappy, value: detectedEntry?.id)
    }

    private var donePage: some View {
        GuidePage(symbol: "sparkles", title: "Tips") {
            StepRow(number: "•", text: "Say **“Log expense in Knock”** to Siri, anywhere.")
            StepRow(number: "•", text: "Prefer a bigger keypad? **Settings → Capture → Open app sheet**.")
            StepRow(number: "•", text: "Back Tap misfiring in your pocket? Use triple tap for both, or adjust in Settings.")
            StepRow(number: "•", text: "You can reopen this guide from **Settings → Back Tap**.")
        }
    }

    private func checkForTestEntry() {
        guard page == 3, detectedEntry == nil else { return }
        let since = startedAt.addingTimeInterval(-120)
        let shortcut = TransactionSource.shortcut.rawValue
        var descriptor = FetchDescriptor<LedgerEntry>(
            predicate: #Predicate { $0.sourceRaw == shortcut && $0.createdAt >= since },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        detectedEntry = try? context.fetch(descriptor).first
    }
}

private struct GuidePage<Content: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, value: symbol)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title2.bold())
                content
            }
            .padding(24)
            .padding(.bottom, 40)
        }
    }
}

private struct StepRow: View {
    let number: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(number)
                .font(.subheadline.bold().monospacedDigit())
                .frame(width: 30, height: 30)
                .glassEffect(.regular, in: .circle)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    BackTapGuide {}
        .previewEnvironment()
}
