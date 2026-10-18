import XCTest

final class PomodoroUITests: XCTestCase {
    func testColdCaptureLinkWorksWithoutProjectsAndSavesUnassignedThought() {
        continueAfterFailure = false
        let app = newApp()
        app.open(URL(string: "pomodoro://thoughts/new")!)
        XCTAssertTrue(app.buttons["thought.capture.done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["thought.project"].exists)
        enterText("Remember this before creating a project", into: "thought.text", in: app)
        app.buttons["thought.capture.add"].tap()
        app.buttons["thought.capture.done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Thoughts"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Thoughts"].tap()
        XCTAssertTrue(app.buttons["Remember this before creating a project"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["timer.countdown"].exists)
    }

    func testBreakDurationIsEditableOnlyBeforeStartAndPlanningStaysAvailable() {
        continueAfterFailure = false
        let app = newApp()
        app.launchEnvironment["POMODORO_TEST_SCENARIO"] = "break-ready"
        app.launch()
        let duration = app.buttons["break.duration"]
        XCTAssertTrue(duration.waitForExistence(timeout: 5))
        duration.tap()
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        wheel.adjust(toPickerWheelValue: "8 min")
        app.buttons["break.duration.cancel"].tap()
        XCTAssertEqual(duration.value as? String, "5 min")
        duration.tap()
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        wheel.adjust(toPickerWheelValue: "8 min")
        app.buttons["break.duration.done"].tap()
        XCTAssertEqual(duration.value as? String, "8 min")
        app.buttons["focus.nextStep"].tap()
        XCTAssertTrue(app.textFields["plan.composer"].waitForExistence(timeout: 5))
        enterText("Review chapter two", into: "plan.composer", in: app)
        app.buttons["plan.add"].tap()
        app.buttons["plan.done"].tap()
        app.buttons["break.start"].tap()
        XCTAssertTrue(app.buttons["timer.end"].waitForExistence(timeout: 5))
        XCTAssertFalse(duration.exists)
        let runningBreakPlan = app.buttons["focus.nextStep"]
        XCTAssertTrue(runningBreakPlan.waitForExistence(timeout: 5))
        runningBreakPlan.tap()
        XCTAssertTrue(app.buttons["Review chapter two"].waitForExistence(timeout: 5))
        app.buttons["plan.done"].tap()
        app.buttons["timer.end"].tap()
        app.buttons["focus.start"].tap()
        let plan = app.buttons["focus.intention.edit"]
        XCTAssertTrue(plan.waitForExistence(timeout: 5))
        XCTAssertEqual(plan.value as? String, "1 task")
        plan.tap()
        XCTAssertTrue(app.buttons["Review chapter two"].waitForExistence(timeout: 5))
    }

    func testEmptyDimFocusCaptureWaitsBeforeReturning() {
        continueAfterFailure = false
        let app = newApp()
        app.launch()
        createProject("Writing", in: app)
        openFocus(in: app)
        app.buttons["focus.start"].tap()
        let toggle = app.buttons["dimFocusToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        let reveal = app.buttons["dimFocusReveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        app.buttons["dimFocusCapture"].tap()
        XCTAssertTrue(app.buttons["thought.capture.done"].waitForExistence(timeout: 5))
        app.buttons["thought.capture.done"].tap()
        XCTAssertFalse(reveal.exists)
        let prematureReturn = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: reveal)
        prematureReturn.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [prematureReturn], timeout: 7), .completed)
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
    }

    func testURLProjectCreationAndTimerRecoveryAcrossRelaunch() {
        continueAfterFailure = false
        let app = newApp()
        app.launchEnvironment["POMODORO_TEST_STORE_ID"] = UUID().uuidString
        app.open(URL(string: "pomodoro://projects/new")!)
        let name = app.textFields["project.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Linked project")
        app.buttons["project.save"].tap()
        XCTAssertTrue(app.buttons["focus.start"].waitForExistence(timeout: 5))
        app.buttons["focus.start"].tap()
        XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Stats"].tap()
        XCTAssertEqual(app.staticTexts["stats.savedFocusTime"].label, "0 min")
        XCTAssertEqual(app.staticTexts["stats.sessionInProgress"].label, "1 session in progress · not included yet")
        // open(_:) relaunches the process and exercises durable timer recovery.
        app.open(URL(string: "pomodoro://timer")!)
        XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Focus"].isSelected)
        app.open(URL(string: "pomodoro://focus?project=AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA&action=start")!)
        XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Linked project"].firstMatch.exists)
        app.buttons["timer.end"].tap()
        app.alerts["End focus?"].buttons["Discard Session"].tap()
        XCTAssertTrue(app.buttons["focus.start"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Stats"].tap()
        XCTAssertTrue(app.staticTexts["No saved sessions"].waitForExistence(timeout: 5))
    }

    func testProjectDailyGoalsDoNotShareSavedTime() {
        let app = newApp()
        app.launchEnvironment["POMODORO_TEST_SCENARIO"] = "project-goals"
        app.launch()
        app.tabBars.buttons["Stats"].tap()
        app.buttons["stats.project"].tap()
        app.buttons["Work"].tap()
        XCTAssertEqual(app.staticTexts["stats.savedFocusTime"].label, "10 min")
        XCTAssertTrue(app.buttons["stats.dailyGoal"].label.contains("4 hr"))
        app.buttons["stats.project"].tap()
        app.buttons["Reading"].tap()
        XCTAssertEqual(app.staticTexts["stats.savedFocusTime"].label, "5 min")
        XCTAssertTrue(app.buttons["stats.dailyGoal"].label.contains("1 hr"))
    }

    func testDiscardAndImmediateHistoryDeletionUndo() {
        continueAfterFailure = false
        let app = newApp()
        app.launch()
        createProject("Writing", in: app)
        openFocus(in: app)
        app.buttons["focus.start"].tap()
        app.buttons["timer.end"].tap()
        let endAlert = app.alerts["End focus?"]
        XCTAssertTrue(endAlert.waitForExistence(timeout: 5))
        XCTAssertTrue(endAlert.buttons["Save Session"].exists)
        XCTAssertTrue(endAlert.buttons["Discard Session"].exists)
        endAlert.buttons["Keep Focusing"].tap()
        XCTAssertTrue(app.staticTexts["timer.countdown"].exists)
        app.buttons["timer.end"].tap()
        endAlert.buttons["Discard Session"].tap()
        XCTAssertTrue(app.buttons["focus.start"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Stats"].tap()
        XCTAssertTrue(app.staticTexts["No saved sessions"].waitForExistence(timeout: 5))

        openFocus(in: app)
        app.buttons["focus.start"].tap()
        app.buttons["timer.end"].tap()
        endAlert.buttons["Save Session"].tap()
        app.tabBars.buttons["Stats"].tap()
        let session = app.descendants(matching: .any).matching(identifier: "session.interrupted").firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.swipeLeft()
        if app.buttons["Delete"].exists { app.buttons["Delete"].tap() }
        XCTAssertFalse(session.exists)
        let undo = app.buttons["session.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(session.waitForExistence(timeout: 5))
    }

    private func newApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--disable-notifications"]
        return app
    }

    private func createProject(_ name: String, in app: XCUIApplication) {
        openProjects(in: app)
        app.buttons["projects.new"].tap()
        let field = app.textFields["project.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.buttons["project.save"].tap()
    }

    private func openFocus(in app: XCUIApplication) {
        if app.tabBars.buttons["Focus"].isSelected { app.tabBars.buttons["Thoughts"].tap() }
        app.tabBars.buttons["Focus"].tap()
    }

    private func openProjects(in app: XCUIApplication) {
        openFocus(in: app)
        app.buttons["focus.more"].tap()
        app.buttons["Manage projects"].tap()
        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 5))
    }

    private func enterText(_ value: String, into identifier: String, in app: XCUIApplication) {
        let text = app.textFields.matching(identifier: identifier).firstMatch.exists ? app.textFields.matching(identifier: identifier).firstMatch : app.textViews.matching(identifier: identifier).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        text.typeText(value)
    }

}
