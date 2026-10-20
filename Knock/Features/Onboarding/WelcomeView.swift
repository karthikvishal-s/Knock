import SwiftUI

/// First launch: one welcome screen, then the Back Tap guide (skippable).
struct WelcomeView: View {
    var onFinish: () -> Void
    @State private var showsGuide = false

    var body: some View {
        if showsGuide {
            BackTapGuide(onFinish: onFinish)
        } else {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                    .padding(28)
                    .glassEffect(.regular.tint(.accentColor.opacity(0.25)), in: .circle)
                    .accessibilityHidden(true)
                Text("Knock")
                    .font(.largeTitle.bold())
                Text("Log every rupee in under three seconds. Double-tap the back of your iPhone — no need to open the app.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
                VStack(alignment: .leading, spacing: 12) {
                    Label("Expenses, income, accounts and budgets", systemImage: "indianrupeesign.circle")
                    Label("Charts that show where it all goes", systemImage: "chart.pie")
                    Label("Everything stays on this iPhone", systemImage: "lock.shield")
                }
                .font(.subheadline)
                .padding(.top, 8)
                Spacer()
                Button {
                    withAnimation { showsGuide = true }
                } label: {
                    Text("Get started")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal)
                Button("Skip Back Tap setup", action: onFinish)
                    .padding(.bottom)
                    .accessibilityIdentifier("welcome-skip")
            }
        }
    }
}

#Preview {
    WelcomeView {}
        .previewEnvironment()
}
