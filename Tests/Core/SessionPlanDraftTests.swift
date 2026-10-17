import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class SessionPlanDraftTests: XCTestCase {
    func testInitializationKeepsOneTrailingPlaceholder() {
        let empty = SessionPlanDraft(text: " \n ")
        XCTAssertEqual(empty.rows.map(\.text), [""])
        XCTAssertFalse(empty.hasChanges)
        let populated = SessionPlanDraft(text: " First\n\nSecond ")
        XCTAssertEqual(populated.rows.map(\.text), ["First", "Second", ""])
        XCTAssertFalse(populated.hasChanges)
    }

    func testTypingPreservesIdentityAndAppendsOnlyOnePlaceholder() {
        var draft = SessionPlanDraft(text: "")
        let first = draft.rows[0].id
        XCTAssertNil(draft.applyEdit(id: first, text: "A"))
        let placeholder = draft.rows[1].id
        XCTAssertNil(draft.applyEdit(id: first, text: "A task"))
        XCTAssertEqual(draft.rows.map(\.id), [first, placeholder])
        XCTAssertTrue(draft.hasChanges)
    }

    func testRepeatedWhitespaceReturnDoesNotAddRows() {
        var draft = SessionPlanDraft(text: "")
        let id = draft.rows[0].id
        XCTAssertNil(draft.applyEdit(id: id, text: " \t"))
        for _ in 0..<4 { XCTAssertNil(draft.applyEdit(id: id, text: " \t\n")) }
        XCTAssertEqual(draft.rows.map(\.id), [id])
        XCTAssertEqual(draft.rows[0].text, " \t")
        XCTAssertFalse(draft.hasChanges)
    }

    func testReturnAdvancesToExistingNextRow() {
        var draft = SessionPlanDraft(text: "First\nSecond")
        let ids = draft.rows.map(\.id)
        XCTAssertEqual(draft.applyEdit(id: ids[0], text: "First\n"), ids[1])
        XCTAssertEqual(draft.applyEdit(id: ids[1], text: "Second\n"), ids[2])
        XCTAssertEqual(draft.rows.map(\.id), ids)
        XCTAssertFalse(draft.hasChanges)
    }

    func testMiddleSplitPreservesBothFragmentsAndOtherIDs() throws {
        var draft = SessionPlanDraft(text: "First second\nLast")
        let ids = draft.rows.map(\.id)
        let target = draft.applyEdit(id: ids[0], text: "First\n second")
        XCTAssertEqual(draft.rows.map(\.text), ["First", " second", "Last", ""])
        XCTAssertEqual(target, draft.rows[1].id)
        XCTAssertEqual([draft.rows[0].id, draft.rows[2].id, draft.rows[3].id], ids)
        XCTAssertEqual(try draft.serialized(), "First\nsecond\nLast")
    }

    func testMultilinePasteDropsBlankLinesAndPreservesPlaceholder() throws {
        var draft = SessionPlanDraft(text: "Before\nAfter")
        let first = draft.rows[0].id
        let placeholder = draft.rows.last!.id
        _ = draft.applyEdit(id: first, text: "\n One\r\n \r\nTwo\rThree\n")
        XCTAssertEqual(draft.rows.map(\.text), [" One", "Two", "Three", "After", ""])
        XCTAssertEqual(draft.rows.last?.id, placeholder)
        XCTAssertEqual(try draft.serialized(), "One\nTwo\nThree\nAfter")
    }

    func testClearedRowSurvivesUntilEditingEnds() {
        var draft = SessionPlanDraft(text: "First\nSecond")
        let first = draft.rows[0].id
        let second = draft.rows[1].id
        let placeholder = draft.rows[2].id
        _ = draft.applyEdit(id: first, text: " ")
        XCTAssertEqual(draft.rows.map(\.id), [first, second, placeholder])
        draft.endEditing(id: first)
        XCTAssertEqual(draft.rows.map(\.id), [second, placeholder])
        draft.endEditing(id: placeholder)
        XCTAssertEqual(draft.rows.map(\.id), [second, placeholder])
    }

    func testEndingEditingOnlyRemovesOutgoingBlankRow() {
        var draft = SessionPlanDraft(text: "First\nSecond")
        let ids = draft.rows.map(\.id)
        _ = draft.applyEdit(id: ids[0], text: "")
        _ = draft.applyEdit(id: ids[1], text: " ")
        draft.endEditing(id: ids[0])
        XCTAssertEqual(draft.rows.map(\.id), [ids[1], ids[2]])
    }

    func testDeletionReturnsSurvivingFocusAndProtectsPlaceholder() {
        var draft = SessionPlanDraft(text: "First\nSecond")
        let ids = draft.rows.map(\.id)
        XCTAssertEqual(draft.remove(id: ids[0]), ids[1])
        XCTAssertEqual(draft.remove(id: ids[1]), ids[2])
        XCTAssertEqual(draft.remove(id: ids[2]), ids[2])
        XCTAssertEqual(draft.rows.map(\.id), [ids[2]])
    }

    func testRevertingChangesRestoresCleanState() throws {
        var draft = SessionPlanDraft(text: " First \n\nSecond ")
        let id = draft.rows[0].id
        _ = draft.applyEdit(id: id, text: "Changed")
        XCTAssertTrue(draft.hasChanges)
        _ = draft.applyEdit(id: id, text: "  First  ")
        XCTAssertFalse(draft.hasChanges)
        XCTAssertEqual(try draft.serialized(), "First\nSecond")
    }

    func testSerializationCountsSeparatorsWithoutTruncation() throws {
        var draft = SessionPlanDraft(text: String(repeating: "a", count: 139))
        let placeholder = draft.rows.last!.id
        _ = draft.applyEdit(id: placeholder, text: String(repeating: "🧠", count: 140))
        XCTAssertEqual(draft.characterCount, 280)
        XCTAssertEqual(try draft.serialized()?.count, 280)
        _ = draft.applyEdit(id: placeholder, text: String(repeating: "🧠", count: 141))
        XCTAssertEqual(draft.characterCount, 281)
        XCTAssertThrowsError(try draft.serialized())
        XCTAssertEqual(draft.rows[1].text.count, 141)
    }
}
