import XCTest

final class PomodoroUITests: XCTestCase {
    func testCreateFocusEndAndReviewInterruptedSession() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--disable-notifications"]
        app.launch()
        app.tabBars.buttons["Projects"].tap()
        app.buttons["projects.new"].tap()
        let field = app.textFields["project.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Writing")
        app.buttons["project.save"].tap()
        app.tabBars.buttons["Focus"].tap()
        app.buttons["focus.start"].tap()
        XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
        app.buttons["timer.end"].tap()
        app.buttons["End and Save Work"].tap()
        app.tabBars.buttons["Stats"].tap()
        let interrupted = app.descendants(matching: .any).matching(identifier: "session.interrupted").firstMatch
        XCTAssertTrue(interrupted.waitForExistence(timeout: 5))
        XCTAssertTrue(interrupted.label.contains("Writing"))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }
}
