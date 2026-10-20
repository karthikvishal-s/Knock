# Knock

Log an expense or income in under three seconds: **double-tap the back of your iPhone**, type the amount, pick a category, done. Knock never needs to open. Inside the app you get history, budgets and Swift Charts analytics.

Personal project. All data stays on the device: no account, no analytics, no ads.

## Status

| Milestone | Scope | State |
|---|---|---|
| M0 | Project setup, App Group + App Intents spikes | ✅ Verified on device |
| M1 | Data model, add/edit/delete transactions, History | ⏳ Next |
| M2 | Back Tap quick-log, Siri, onboarding guide | |
| M3 | Accounts, transfers, income | |
| M4 | Analytics | |
| M5 | Budgets, recurring, notifications | |
| M6 | Widgets, Lock Screen, Control Center | |
| M7 | CSV/JSON import & export, Face ID lock | |
| M8 | Polish & performance | |

The full design is in [PLAN.md](PLAN.md).

## Requirements

- Xcode 27.1+ (Swift 6.4, iOS 27 SDK)
- iPhone on iOS 27
- An Apple ID. A free Personal Team works; the app must be re-run from Xcode every 7 days.

## Project layout

```
Knock/            iOS app (SwiftUI, App Intents)
KnockWidgets/     Widget extension (Home/Lock Screen widgets, Control Center controls)
KnockKit/         Local Swift package: models, persistence, domain logic. Shared by both targets
Config/           Entitlements and the widget Info.plist
```

## Build & run

1. Open `Knock.xcodeproj`.
2. Under **Signing & Capabilities**, set your Team for the `Knock` and `KnockWidgetsExtension` targets.
3. Choose your iPhone (Developer Mode on) and press **Run**.

## Tests

```sh
cd KnockKit && swift test   # domain + persistence tests, run on the Mac
```

## Set up Back Tap

Create a shortcut in the Shortcuts app with Knock's **Log Expense** action, then choose it under
**Settings → Accessibility → Touch → Back Tap → Double Tap**. Use **Log Income** for Triple Tap.
