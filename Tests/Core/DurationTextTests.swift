import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class DurationTextTests: XCTestCase {
    func testSummaryFormatsMinuteAndHourBoundaries() {
        let cases: [(TimeInterval, String)] = [
            (-60, "0 min"),
            (0, "0 min"),
            (0.001, "<1 min"),
            (59, "<1 min"),
            (59.999, "<1 min"),
            (60, "1 min"),
            (60.001, "1 min"),
            (119.999, "1 min"),
            (120, "2 min"),
            (3599.999, "59 min"),
            (3600, "1 hr"),
            (3600.001, "1 hr"),
            (3659.999, "1 hr"),
            (3660, "1 hr 1 min"),
            (7200, "2 hr"),
            (8159.999, "2 hr 15 min")
        ]
        for (seconds, expected) in cases {
            XCTAssertEqual(DurationText.summary(seconds), expected, "Duration: \(seconds)")
        }
    }

    func testDetailedAndCountdownFormattingRetainSeconds() {
        XCTAssertEqual(DurationText.work(59.999), "59 sec")
        XCTAssertEqual(DurationText.work(0), "0 sec")
        XCTAssertEqual(DurationText.countdown(59.001), "01:00")
        XCTAssertEqual(DurationText.countdown(60), "01:00")
        XCTAssertEqual(DurationText.countdown(-1), "00:00")
    }
}
