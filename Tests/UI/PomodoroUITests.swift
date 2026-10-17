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

    func testDimFocusCaptureAndTemporaryRevealRespectSheetAndTab() {
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
        enterText("Preserve capture while focus is dimmed", into: "thought.text", in: app)
        let prematureDim = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: reveal)
        prematureDim.isInverted = true
        wait(for: [prematureDim], timeout: 11)
        XCTAssertTrue((thoughtInput(in: app).value as? String)?.contains("Preserve capture") == true)
        app.buttons["thought.capture.add"].tap()
        app.buttons["thought.capture.done"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let dimImmediatelyAfterSave = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: reveal)
        dimImmediatelyAfterSave.isInverted = true
        wait(for: [dimImmediatelyAfterSave], timeout: 6)
        XCTAssertTrue(reveal.waitForExistence(timeout: 10))

        app.buttons["dimFocusCapture"].tap()
        XCTAssertTrue(app.buttons["thought.capture.done"].waitForExistence(timeout: 5))
        app.buttons["thought.capture.done"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let dimImmediatelyAfterEmptyCapture = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: reveal)
        dimImmediatelyAfterEmptyCapture.isInverted = true
        wait(for: [dimImmediatelyAfterEmptyCapture], timeout: 6)
        XCTAssertTrue(reveal.waitForExistence(timeout: 10))
        reveal.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        app.tabBars.buttons["Thoughts"].tap()
        let dimOnOtherTab = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: reveal)
        dimOnOtherTab.isInverted = true
        wait(for: [dimOnOtherTab], timeout: 11)
        XCTAssertTrue(app.buttons["Preserve capture while focus is dimmed"].exists)
        app.tabBars.buttons["Focus"].tap()
        XCTAssertTrue(reveal.waitForExistence(timeout: 15))
        reveal.tap()
        toggle.tap()
        let dimAfterDisable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: reveal)
        dimAfterDisable.isInverted = true
        wait(for: [dimAfterDisable], timeout: 11)
        XCTAssertTrue(app.staticTexts["timer.countdown"].exists)
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

    func testQuickStartSetupShowsInvalidURLAndCreatesShortcutWithoutStarting() {
        continueAfterFailure = false
        let app = newApp()
        app.launch()
        createProject("Writing", in: app)
        openSettings(in: app)
        app.buttons["settings.quickstart"].tap()
        let connection = app.buttons["quickstart.connection"]
        if connection.exists {
            connection.tap()
            let toggle = app.switches["quickstart.useContainer"]
            if toggle.value as? String == "0" { toggle.tap() }
            let field = app.textFields["quickstart.launchURL"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            replaceText(in: field, with: "https://example.com")
            app.buttons["quickstart.connection.save"].tap()
            XCTAssertTrue(app.staticTexts["quickstart.invalidURL"].waitForExistence(timeout: 5))
            let validURL = "livecontainer2://livecontainer-launch?bundle-name=Pomodoro.app&container-folder-name=test"
            field.tap()
            replaceText(in: field, with: validURL)
            app.buttons["quickstart.connection.save"].tap()
            XCTAssertTrue(app.buttons["quickstart.copy"].waitForExistence(timeout: 5))
            connection.tap()
            field.tap()
            replaceText(in: field, with: "https://invalid.example.com")
            app.buttons["quickstart.connection.save"].tap()
            XCTAssertTrue(app.staticTexts["quickstart.invalidURL"].waitForExistence(timeout: 5))
            app.navigationBars.buttons.firstMatch.tap()
            connection.tap()
            XCTAssertEqual(field.value as? String, validURL)
            app.navigationBars.buttons.firstMatch.tap()
        }
        let copy = app.buttons["quickstart.copy"]
        reveal(copy, in: app, scrollingUp: true)
        XCTAssertTrue(copy.isEnabled)
        copy.tap()
        XCTAssertTrue(app.staticTexts["quickstart.copied"].waitForExistence(timeout: 5))
        openFocus(in: app)
        XCTAssertTrue(app.buttons["focus.start"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["timer.countdown"].exists)
    }

    func testCreateFocusEndAndReviewSession() {
        let app = newApp()
        app.launch()
        XCTAssertEqual(app.tabBars.buttons.count, 3)
        XCTAssertFalse(app.tabBars.buttons["Projects"].exists)
        XCTAssertFalse(app.tabBars.buttons["Settings"].exists)
        createProject("Writing", in: app)
        openFocus(in: app)
        app.buttons["focus.start"].tap()
        XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
        app.buttons["timer.end"].tap()
        app.alerts["End focus?"].buttons["Save Session"].tap()
        app.tabBars.buttons["Stats"].tap()
        let session = app.descendants(matching: .any).matching(identifier: "session.interrupted").firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        XCTAssertTrue(session.label.contains("Writing"))
        XCTAssertFalse(app.staticTexts["stats.sessionInProgress"].exists)
        XCTAssertNotEqual(app.staticTexts["stats.savedFocusTime"].label, "0 min")
        XCTAssertFalse(planInput(in: app).exists)
        XCTAssertFalse(app.textFields["breadcrumb.text"].exists)
        app.buttons["stats.dailyGoal"].tap()
        XCTAssertTrue(app.navigationBars["Daily goals"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["stats.more"].tap()
        app.buttons["Goals"].tap()
        XCTAssertTrue(app.navigationBars["Goals"].waitForExistence(timeout: 5))
        app.buttons["Consistency"].tap()
        app.buttons["consistency.target"].tap()
        app.buttons["7 days"].tap()
        XCTAssertTrue(app.staticTexts["0 of 7 focused days"].waitForExistence(timeout: 5))
        openSettings(in: app)
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }

    func testSavedStatisticsStayStableWhileFocusRuns() {
        continueAfterFailure = false
        let app = newApp()
        app.launchEnvironment["POMODORO_TEST_SCENARIO"] = "saved-stats"
        app.launch()
        app.tabBars.buttons["Stats"].tap()
        app.buttons["All"].tap()
        let total = app.staticTexts["stats.savedFocusTime"]
        let status = app.staticTexts["stats.sessionInProgress"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertEqual(total.label, "25 min")
        XCTAssertTrue(status.exists)
        XCTAssertFalse(app.staticTexts["In progress"].exists)
        for range in ["Today", "Week", "Month", "All"] {
            app.buttons[range].tap()
            let savedValue = total.label
            XCTAssertTrue(status.exists)
            app.tabBars.buttons["Thoughts"].tap()
            app.tabBars.buttons["Stats"].tap()
            XCTAssertEqual(total.label, savedValue)
        }
        app.buttons["stats.project"].tap()
        app.buttons["Study"].tap()
        XCTAssertEqual(total.label, "0 min")
        XCTAssertFalse(status.exists)
        XCTAssertTrue(app.staticTexts["No saved sessions"].exists)
        app.buttons["stats.project"].tap()
        app.buttons["All projects"].tap()
        XCTAssertEqual(total.label, "25 min")
        XCTAssertTrue(status.exists)
        openFocus(in: app)
        app.buttons["timer.end"].tap()
        app.alerts["End focus?"].buttons["Discard Session"].tap()
        app.tabBars.buttons["Stats"].tap()
        XCTAssertEqual(total.label, "25 min")
        XCTAssertFalse(status.exists)
    }

    func testDurationWheelRemembersProjectAndRunningTimerIsReadOnly() {
        continueAfterFailure = false
        let app = newApp()
        app.launch()
        createProject("Writing", in: app)
        createProject("Study", in: app)
        openFocus(in: app)
        chooseProject("Writing", in: app)
        setDuration("40 min", in: app)
        assertDuration("40 min", in: app)
        app.tabBars.buttons["Stats"].tap()
        openFocus(in: app)
        assertDuration("40 min", in: app)
        chooseProject("Study", in: app)
        assertDuration("25 min", in: app)
        setDuration("15 min", in: app)
        chooseProject("Writing", in: app)
        assertDuration("40 min", in: app)
        setDuration("50 min", in: app, save: false)
        assertDuration("40 min", in: app)
        attachScreenshot("Focus ready", app: app)
        app.buttons["focus.start"].tap()
        XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["focus.duration"].exists)
        attachScreenshot("Focus running", app: app)
        openProjects(in: app)
        app.buttons["Study"].tap()
        XCTAssertTrue(app.navigationBars["Study"].waitForExistence(timeout: 5))
        openSettings(in: app)
        openFocus(in: app)
        XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Writing"].exists)
        app.buttons["timer.end"].tap()
        app.alerts["End focus?"].buttons["Save Session"].tap()
        assertDuration("40 min", in: app)
        chooseProject("Study", in: app)
        assertDuration("15 min", in: app)
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

    func testSessionNoteThoughtBreadcrumbAndStatistics() {
        continueAfterFailure = false
        let app = newApp()
        app.launch()
        createProject("Writing", in: app)
        openFocus(in: app)
        XCTAssertFalse(app.buttons["focus.intention"].exists)
        app.buttons["focus.more"].tap()
        app.buttons["Plan this session"].tap()
        addPlanTasks("Draft introduction", in: app)
        app.buttons["plan.done"].tap()
        openSettings(in: app)
        openFocus(in: app)
        openProjects(in: app)
        app.tabBars.buttons["Thoughts"].tap()
        openFocus(in: app)
        assertPlanSummary("focus.intention", count: 1, in: app)
        XCTAssertFalse(app.staticTexts["Draft introduction"].exists)
        app.buttons["focus.start"].tap()
        let capture = app.buttons["focus.captureThought"]
        reveal(capture, in: app, scrollingUp: false)
        capture.tap()
        enterText("Find the source later", into: "thought.text", in: app)
        app.buttons["thought.capture.add"].tap()
        app.buttons["thought.capture.done"].tap()
        app.buttons["timer.end"].tap()
        app.alerts["End focus?"].buttons["Save Session"].tap()
        let next = app.buttons["focus.nextStep"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        enterText("Continue with methods", into: "breadcrumb.text", in: app)
        app.buttons["breadcrumb.save"].tap()
        app.tabBars.buttons["Stats"].tap()
        let session = app.descendants(matching: .any).matching(identifier: "session.interrupted").firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        XCTAssertTrue(session.label.contains("Draft introduction"))
        app.buttons["Week"].tap()
        XCTAssertTrue(app.staticTexts["Saved focus time"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Thoughts"].tap()
        let check = app.buttons["thought.check"].firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        XCTAssertEqual(check.value as? String, "Open")
        check.tap()
        XCTAssertTrue(app.staticTexts["All caught up"].waitForExistence(timeout: 5))
        app.buttons["View completed"].tap()
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        XCTAssertEqual(check.value as? String, "Done")
        check.tap()
        XCTAssertTrue(app.staticTexts["No matching thoughts"].waitForExistence(timeout: 5))
        filterThoughts("Open", in: app)
        XCTAssertTrue(check.waitForExistence(timeout: 5))
    }

    func testSessionPlanComposerAndSessionThoughtCapture() {
        continueAfterFailure = false
        let app = newApp()
        app.launch()
        createProject("Writing", in: app)
        openFocus(in: app)
        app.buttons["focus.more"].tap()
        app.buttons["Plan this session"].tap()
        let composer = planInput(in: app)
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Session plan"].exists)
        XCTAssertFalse(app.staticTexts["What do you want to achieve?"].exists)
        XCTAssertFalse(app.buttons["plan.add"].isEnabled)
        composer.tap()
        composer.typeText("   \n\n")
        XCTAssertFalse(app.buttons["plan.add"].isEnabled)
        replaceText(in: composer, with: "Draft introduction")
        XCTAssertFalse(app.buttons["Draft introduction"].exists)
        app.buttons["plan.add"].tap()
        XCTAssertTrue(app.buttons["Draft introduction"].waitForExistence(timeout: 5))
        XCTAssertTrue(composer.isHittable)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.buttons["plan.add"].isEnabled)
        addPlanTasks("Find references\nReview conclusion", in: app)
        XCTAssertTrue(app.buttons["Find references"].exists)
        XCTAssertTrue(app.buttons["Review conclusion"].exists)
        enterText("Pending task", into: "plan.composer", in: app)
        app.buttons["Find references"].tap()
        let taskEditor = app.descendants(matching: .any).matching(identifier: "plan.task.edit").firstMatch
        XCTAssertTrue(taskEditor.waitForExistence(timeout: 5))
        taskEditor.tap()
        replaceText(in: taskEditor, with: "Find primary references")
        app.buttons["plan.task.save"].tap()
        XCTAssertTrue(app.buttons["Find primary references"].waitForExistence(timeout: 5))
        XCTAssertEqual(planInput(in: app).value as? String, "Pending task")
        app.buttons["plan.done"].tap()
        app.buttons["Keep editing"].tap()
        XCTAssertEqual(planInput(in: app).value as? String, "Pending task")
        app.buttons["plan.done"].tap()
        app.buttons["Discard draft"].tap()
        assertPlanSummary("focus.intention", count: 3, in: app)
        XCTAssertFalse(app.staticTexts["Draft introduction"].exists)
        app.buttons["focus.intention"].tap()
        XCTAssertFalse(app.buttons["Pending task"].exists)
        XCTAssertTrue(app.buttons["Find primary references"].exists)
        app.buttons["Review conclusion"].swipeLeft()
        app.buttons["Delete"].tap()
        app.buttons["plan.done"].tap()
        assertPlanSummary("focus.intention", count: 2, in: app)
        app.buttons["focus.intention"].tap()
        XCTAssertFalse(app.buttons["Review conclusion"].exists)
        app.buttons["plan.done"].tap()
        app.buttons["focus.start"].tap()
        let capture = app.buttons["focus.captureThought"]
        reveal(capture, in: app)
        capture.tap()
        enterText("Find source later", into: "thought.text", in: app)
        app.buttons["thought.capture.add"].tap()
        XCTAssertTrue(app.buttons["Find source later"].waitForExistence(timeout: 5))
        XCTAssertTrue(thoughtInput(in: app).isHittable)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["thought.capture.add"].isEnabled)
        enterText("Ask about figures", into: "thought.text", in: app)
        app.buttons["thought.capture.add"].tap()
        enterText("Pending composer text", into: "thought.text", in: app)
        app.buttons["Ask about figures"].tap()
        let editingText = thoughtInput(in: app)
        XCTAssertTrue(editingText.waitForExistence(timeout: 5))
        editingText.tap()
        replaceText(in: editingText, with: "Ask Sam about figures")
        app.buttons["thought.save"].tap()
        XCTAssertTrue(app.buttons["Ask Sam about figures"].waitForExistence(timeout: 5))
        XCTAssertEqual(thoughtInput(in: app).value as? String, "Pending composer text")
        thoughtInput(in: app).tap()
        replaceText(in: thoughtInput(in: app), with: "")
        app.buttons["thought.check"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Find source later"].exists)
        XCTAssertEqual(app.buttons["thought.check"].firstMatch.value as? String, "Done")
        app.buttons["thought.capture.done"].tap()
        capture.tap()
        XCTAssertTrue(app.buttons["Find source later"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Ask Sam about figures"].exists)
        XCTAssertEqual(app.buttons["thought.check"].firstMatch.value as? String, "Done")
        enterText("Unsaved draft", into: "thought.text", in: app)
        app.buttons["thought.capture.done"].tap()
        app.buttons["Keep editing"].tap()
        XCTAssertEqual(thoughtInput(in: app).value as? String, "Unsaved draft")
        XCTAssertEqual(app.buttons.matching(identifier: "thought.check").count, 2)
        app.buttons["thought.capture.done"].tap()
        app.buttons["Discard draft"].tap()
        capture.tap()
        XCTAssertFalse(app.buttons["Unsaved draft"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "thought.check").count, 2)
        enterText("Check table captions", into: "thought.text", in: app)
        app.buttons["thought.capture.add"].tap()
        XCTAssertTrue(app.buttons["Check table captions"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "thought.check").count, 3)
        app.buttons["thought.capture.done"].tap()
        app.buttons["timer.end"].tap()
        app.alerts["End focus?"].buttons["Discard Session"].tap()
        app.buttons["focus.start"].tap()
        capture.tap()
        XCTAssertFalse(app.buttons["Find source later"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "thought.check").count, 0)
        app.buttons["thought.capture.done"].tap()
        app.tabBars.buttons["Thoughts"].tap()
        filterThoughts("All", in: app)
        XCTAssertTrue(app.buttons["Find source later"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Check table captions"].exists)
    }

    func testSessionPlanPersistsActiveAndSavedEdits() {
        continueAfterFailure = false
        let app = newApp()
        app.launch()
        createProject("Writing", in: app)
        openFocus(in: app)
        app.buttons["focus.start"].tap()
        XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["focus.intention.edit"].exists)
        app.buttons["focus.more"].tap()
        app.buttons["Plan this session"].tap()
        addPlanTasks("Write first draft", in: app)
        app.buttons["plan.done"].tap()
        assertPlanSummary("focus.intention.edit", count: 1, in: app)
        XCTAssertFalse(app.staticTexts["Write first draft"].exists)
        app.buttons["focus.intention.edit"].tap()
        XCTAssertTrue(app.buttons["Write first draft"].waitForExistence(timeout: 5))
        addPlanTasks("Review sources", in: app)
        app.buttons["Write first draft"].tap()
        let taskEditor = app.descendants(matching: .any).matching(identifier: "plan.task.edit").firstMatch
        XCTAssertTrue(taskEditor.waitForExistence(timeout: 5))
        taskEditor.tap()
        replaceText(in: taskEditor, with: "Cancelled edit")
        app.buttons["plan.task.cancel"].tap()
        XCTAssertTrue(app.buttons["Write first draft"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Cancelled edit"].exists)
        app.buttons["plan.done"].tap()
        assertPlanSummary("focus.intention.edit", count: 2, in: app)
        XCTAssertTrue(app.staticTexts["timer.countdown"].exists)
        reveal(app.buttons["timer.end"], in: app)
        app.buttons["timer.end"].tap()
        app.alerts["End focus?"].buttons["Save Session"].tap()
        app.tabBars.buttons["Stats"].tap()
        let session = app.descendants(matching: .any).matching(identifier: "session.interrupted").firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        XCTAssertTrue(session.label.contains("Write first draft"))
        session.tap()
        XCTAssertTrue(app.navigationBars["Session"].waitForExistence(timeout: 5))
        app.buttons["Edit this session"].tap()
        XCTAssertTrue(app.buttons["Review sources"].waitForExistence(timeout: 5))
        app.buttons["Write first draft"].tap()
        XCTAssertTrue(taskEditor.waitForExistence(timeout: 5))
        taskEditor.tap()
        replaceText(in: taskEditor, with: "Revise first draft")
        app.buttons["plan.task.save"].tap()
        app.buttons["Review sources"].swipeLeft()
        app.buttons["Delete"].tap()
        app.buttons["plan.done"].tap()
        app.buttons["Edit this session"].tap()
        XCTAssertTrue(app.buttons["Revise first draft"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Review sources"].exists)
        app.buttons["Revise first draft"].swipeLeft()
        app.buttons["Delete"].tap()
        app.buttons["plan.done"].tap()
        XCTAssertTrue(app.buttons["Plan this session"].waitForExistence(timeout: 5))
    }

    func testStandaloneCaptureVisitShowsOnlyNewEntries() {
        continueAfterFailure = false
        let app = newApp()
        app.launch()
        app.tabBars.buttons["Thoughts"].tap()
        app.buttons["thoughts.new"].tap()
        enterText("First visit thought", into: "thought.text", in: app)
        app.buttons["thought.capture.add"].tap()
        enterText("Another first visit thought", into: "thought.text", in: app)
        app.buttons["thought.capture.add"].tap()
        XCTAssertTrue(thoughtInput(in: app).isHittable)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["thought.capture.add"].isEnabled)
        enterText("   ", into: "thought.text", in: app)
        XCTAssertFalse(app.buttons["thought.capture.add"].isEnabled)
        replaceText(in: thoughtInput(in: app), with: "Third first visit thought")
        app.buttons["thought.capture.add"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "thought.check").count, 3)
        XCTAssertTrue(thoughtInput(in: app).isHittable)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.buttons["thought.capture.done"].tap()
        app.buttons["thoughts.new"].tap()
        XCTAssertFalse(app.buttons["First visit thought"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "thought.check").count, 0)
        enterText("Second visit thought", into: "thought.text", in: app)
        app.buttons["thought.capture.add"].tap()
        app.buttons["thought.capture.done"].tap()
        XCTAssertTrue(app.buttons["First visit thought"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Another first visit thought"].exists)
        XCTAssertTrue(app.buttons["Third first visit thought"].exists)
        XCTAssertTrue(app.buttons["Second visit thought"].exists)
    }

    func testStandaloneThoughtSearchUnassignedCheckDeleteAndUndo() {
        continueAfterFailure = false
        let app = newApp()
        app.launch()
        app.tabBars.buttons["Thoughts"].tap()
        app.buttons["thoughts.new"].tap()
        enterText("Review bibliography", into: "thought.text", in: app)
        app.buttons["thought.capture.add"].tap()
        app.buttons["thought.capture.done"].tap()
        let thought = app.buttons["Review bibliography"].firstMatch
        XCTAssertTrue(thought.waitForExistence(timeout: 5))
        app.buttons["thoughts.filters"].tap()
        app.buttons["thoughts.project"].tap()
        app.buttons["Unassigned"].tap()
        XCTAssertTrue(thought.exists)
        let search = app.searchFields.firstMatch
        reveal(search, in: app, scrollingUp: false)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("bibliography")
        XCTAssertTrue(thought.exists)
        replaceText(in: search, with: "missing")
        XCTAssertTrue(app.staticTexts["No matching thoughts"].waitForExistence(timeout: 5))
        reveal(app.buttons["thoughts.reset"], in: app)
        app.buttons["thoughts.reset"].tap()
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        XCTAssertTrue(thought.waitForExistence(timeout: 5))
        let check = app.buttons["thought.check"].firstMatch
        check.tap()
        filterThoughts("Done", in: app)
        XCTAssertEqual(check.value as? String, "Done")
        thought.swipeLeft()
        if app.buttons["Delete"].exists { app.buttons["Delete"].tap() }
        XCTAssertFalse(thought.exists)
        let undo = app.buttons["session.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(thought.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["thought.check"].firstMatch.value as? String, "Done")
        app.buttons["thoughts.more"].tap()
        app.buttons["thoughts.select"].tap()
        app.buttons["thought.check"].firstMatch.tap()
        app.buttons["Mark"].tap()
        app.buttons["Open"].tap()
        XCTAssertFalse(thought.exists)
        app.buttons["thoughts.reset"].tap()
        XCTAssertTrue(thought.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["thought.check"].firstMatch.value as? String, "Open")
    }

    func testVisualStatesLightDarkAndAccessibilityText() {
        continueAfterFailure = false
        for (name, appearance, textSize) in [
            ("Light", "light", "standard"),
            ("Dark", "dark", "standard"),
            ("Large text", "dark", "accessibility2")
        ] {
            let app = newApp()
            app.launchEnvironment["POMODORO_TEST_APPEARANCE"] = appearance
            app.launchEnvironment["POMODORO_TEST_DYNAMIC_TYPE"] = textSize
            app.launch()
            createProject("A long project name for layout checks", in: app)
            openFocus(in: app)
            XCTAssertTrue(app.buttons["focus.start"].waitForExistence(timeout: 5))
            if textSize == "standard" {
                XCTAssertTrue(app.buttons["focus.start"].isHittable)
                XCTAssertTrue(app.buttons["focus.duration"].isHittable)
            }
            attachScreenshot("\(name) · Focus ready", app: app)
            app.buttons["focus.more"].tap()
            app.buttons["Plan this session"].tap()
            addPlanTasks("Draft the introduction\nReview references", in: app)
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            attachScreenshot("\(name) · Session plan with keyboard", app: app)
            app.buttons["plan.done"].tap()
            assertPlanSummary("focus.intention", count: 2, in: app)
            attachScreenshot("\(name) · Focus ready with session plan", app: app)
            reveal(app.buttons["focus.start"], in: app)
            app.buttons["focus.start"].tap()
            XCTAssertTrue(app.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
            assertPlanSummary("focus.intention.edit", count: 2, in: app)
            attachScreenshot("\(name) · Focus running", app: app)
            app.tabBars.buttons["Stats"].tap()
            XCTAssertEqual(app.staticTexts["stats.savedFocusTime"].label, "0 min")
            XCTAssertTrue(app.staticTexts["stats.sessionInProgress"].exists)
            attachScreenshot("\(name) · Stats during focus", app: app)
            openFocus(in: app)
            app.buttons["focus.captureThought"].tap()
            enterText("A thought saved during focus", into: "thought.text", in: app)
            app.buttons["thought.capture.add"].tap()
            XCTAssertTrue(thoughtInput(in: app).isHittable)
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            attachScreenshot("\(name) · Session thoughts with keyboard", app: app)
            app.buttons["thought.capture.done"].tap()
            app.buttons["timer.end"].tap()
            app.alerts["End focus?"].buttons["Save Session"].tap()
            attachScreenshot("\(name) · Focus after saving", app: app)
            app.tabBars.buttons["Stats"].tap()
            attachScreenshot("\(name) · Stats", app: app)
            app.buttons["Week"].tap()
            attachScreenshot("\(name) · Weekly stats", app: app)
            app.buttons["Month"].tap()
            attachScreenshot("\(name) · Monthly stats", app: app)
            let details = app.buttons["Details"]
            reveal(details, in: app)
            details.tap()
            XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
            app.tabBars.buttons["Thoughts"].tap()
            attachScreenshot("\(name) · Thoughts", app: app)
            openSettings(in: app)
            attachScreenshot("\(name) · Settings", app: app)
            app.terminate()
            let breakApp = newApp()
            breakApp.launchEnvironment["POMODORO_TEST_SCENARIO"] = "break-ready"
            breakApp.launchEnvironment["POMODORO_TEST_APPEARANCE"] = appearance.lowercased()
            if name == "Large text" { breakApp.launchEnvironment["POMODORO_TEST_DYNAMIC_TYPE"] = "accessibility2" }
            breakApp.launch()
            let startBreak = breakApp.buttons["Start Break"]
            XCTAssertTrue(startBreak.waitForExistence(timeout: 5))
            XCTAssertFalse(planInput(in: breakApp).exists)
            XCTAssertFalse(breakApp.textFields["breadcrumb.text"].exists)
            XCTAssertEqual(breakApp.alerts.count, 0)
            attachScreenshot("\(name) · Break ready", app: breakApp)
            reveal(startBreak, in: breakApp)
            startBreak.tap()
            XCTAssertTrue(breakApp.staticTexts["timer.countdown"].waitForExistence(timeout: 5))
            attachScreenshot("\(name) · Break running", app: breakApp)
            breakApp.terminate()
        }
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

    private func openSettings(in app: XCUIApplication) {
        openFocus(in: app)
        app.buttons["focus.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    private func filterThoughts(_ status: String, in app: XCUIApplication) {
        app.buttons["thoughts.filters"].tap()
        app.buttons[status].tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, scrollingUp: Bool = true) {
        for _ in 0..<5 {
            if element.isHittable { return }
            if scrollingUp { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable)
    }

    private func chooseProject(_ name: String, in app: XCUIApplication) {
        let picker = app.buttons["focus.project"]
        reveal(picker, in: app)
        picker.tap()
        app.buttons[name].tap()
    }

    private func setDuration(_ value: String, in app: XCUIApplication, save: Bool = true) {
        let button = app.buttons["focus.duration"]
        reveal(button, in: app)
        button.tap()
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        wheel.adjust(toPickerWheelValue: value)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", value), object: wheel)
        changed.isInverted = true
        wait(for: [changed], timeout: 3)
        XCTAssertEqual(wheel.value as? String, value)
        app.buttons[save ? "focus.duration.done" : "focus.duration.cancel"].tap()
    }

    private func assertDuration(_ value: String, in app: XCUIApplication) {
        let button = app.buttons["focus.duration"]
        reveal(button, in: app)
        XCTAssertEqual(button.value as? String, value)
    }

    private func planInput(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "plan.composer").firstMatch
    }

    private func addPlanTasks(_ value: String, in app: XCUIApplication) {
        enterText(value, into: "plan.composer", in: app)
        XCTAssertTrue(app.buttons["plan.add"].isEnabled)
        app.buttons["plan.add"].tap()
    }

    private func assertPlanSummary(_ identifier: String, count: Int, in app: XCUIApplication) {
        let row = app.buttons[identifier]
        reveal(row, in: app)
        XCTAssertEqual(row.label, "Open session plan")
        XCTAssertEqual(row.value as? String, count == 1 ? "1 task" : "\(count) tasks")
    }

    private func thoughtInput(in app: XCUIApplication) -> XCUIElement {
        let inputs = app.descendants(matching: .any).matching(identifier: "thought.text")
        for input in inputs.allElementsBoundByIndex.reversed() where input.isHittable {
            return input
        }
        return inputs.element(boundBy: max(0, inputs.count - 1))
    }

    private func enterText(_ value: String, into identifier: String, in app: XCUIApplication) {
        let text = app.textFields.matching(identifier: identifier).firstMatch.exists ? app.textFields.matching(identifier: identifier).firstMatch : app.textViews.matching(identifier: identifier).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        text.typeText(value)
    }

    private func replaceText(in field: XCUIElement, with value: String) {
        let previous = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        field.typeText(value)
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
