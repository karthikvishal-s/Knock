import XCTest

/// Walks the main screens with sample data and attaches screenshots — a visual check that
/// also catches crashes on every tab.
@MainActor
final class ScreenshotTests: XCTestCase {
    func testCaptureMainScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-sample-data"]
        app.launch()

        snap(app, "1-Home")
        app.tabBars.buttons["History"].tap()
        snap(app, "2-History")

        app.tabBars.buttons["Analytics"].tap()
        XCTAssertTrue(app.staticTexts["Spending by category"].waitForExistence(timeout: 10))
        snap(app, "3-Analytics-top")
        for index in 1...4 {
            app.swipeUp()
            snap(app, "3-Analytics-\(index)")
        }

        app.tabBars.buttons["Budgets"].tap()
        snap(app, "4-Budgets")
        app.tabBars.buttons["Settings"].tap()
        snap(app, "5-Settings")
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Dark mode at the largest accessibility text size: catches clipped or overlapping text.
@MainActor
final class AccessibilityScreenshotTests: XCTestCase {
    func testDarkModeLargestText() throws {
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-sample-data", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        for tab in ["Home", "History", "Analytics", "Budgets", "Settings"] {
            app.tabBars.buttons[tab].tap()
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "AX-\(tab)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app.tabBars.buttons["Home"].tap()
        app.buttons["add-button"].tap()
        XCTAssertTrue(app.buttons["save-button"].waitForExistence(timeout: 3))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "AX-QuickEntry"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
