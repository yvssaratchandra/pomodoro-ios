import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class QuickStartLinksTests: XCTestCase {
    func testForwardingPreservesInstanceAndContainerParameters() throws {
        let source = try XCTUnwrap(URL(string: "livecontainer2://livecontainer-launch?bundle-name=Pomodoro.app&container-folder-name=Notes%20%2B%20%E6%97%A5%E6%9C%AC%E8%AA%9E&jit=true&extra=keep%3Dthis"))
        let launch = try LiveContainerLaunchURL(source)
        let guest = AppURLRouter(scheme: .container).url(for: .startFocus(projectID: UUID()))
        let forwarded = launch.url(forwarding: guest)
        let components = try XCTUnwrap(URLComponents(url: forwarded, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "livecontainer2")
        XCTAssertEqual(components.host, "livecontainer-launch")
        let items = try XCTUnwrap(components.queryItems)
        XCTAssertEqual(items.first { $0.name == "bundle-name" }?.value, "Pomodoro.app")
        XCTAssertEqual(items.first { $0.name == "container-folder-name" }?.value, "Notes + 日本語")
        XCTAssertEqual(items.first { $0.name == "jit" }?.value, "true")
        XCTAssertEqual(items.first { $0.name == "extra" }?.value, "keep=this")
        XCTAssertEqual(try forwardedGuest(forwarded), guest.absoluteString)
    }

    func testForwardingReplacesOldGuestAndFallbackOnlyLaunchesApp() throws {
        let source = try XCTUnwrap(URL(string: "livecontainer://livecontainer-launch?bundle-name=Pomodoro.app&open-url=b2xk&jit=false"))
        let launch = try LiveContainerLaunchURL(source)
        let guest = AppURLRouter(scheme: .container).url(for: .timer)
        let result = launch.url(forwarding: guest)
        let items = try XCTUnwrap(URLComponents(url: result, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.filter { $0.name == "open-url" }.count, 1)
        XCTAssertEqual(try forwardedGuest(result), guest.absoluteString)
        let fallback = try XCTUnwrap(URLComponents(url: launch.launchURL, resolvingAgainstBaseURL: false))
        XCTAssertFalse(try XCTUnwrap(fallback.queryItems).contains { $0.name == "open-url" })
        XCTAssertEqual(fallback.queryItems?.first { $0.name == "bundle-name" }?.value, "Pomodoro.app")
        XCTAssertEqual(fallback.queryItems?.first { $0.name == "jit" }?.value, "false")
    }

    func testBase64PlusPaddingAndUnicodeURLRoundTrip() throws {
        let launch = try LiveContainerLaunchURL(XCTUnwrap(URL(string: "livecontainer://livecontainer-launch?bundle-name=Pomodoro.app")))
        let guests = ["pomodoro://timer?value=~~~", "pomodoro://timer?value=日本語🧠", "pomodoro://timer"]
        var sawPlus = false
        var sawPadding = false
        for text in guests {
            let guest = try XCTUnwrap(URL(string: text))
            let value = Data(guest.absoluteString.utf8).base64EncodedString()
            sawPlus = sawPlus || value.contains("+")
            sawPadding = sawPadding || value.contains("=")
            let result = launch.url(forwarding: guest)
            XCTAssertEqual(try forwardedGuest(result), guest.absoluteString)
            if value.contains("+") { XCTAssertTrue(result.absoluteString.contains("%2B")) }
        }
        XCTAssertTrue(sawPlus)
        XCTAssertTrue(sawPadding)
    }

    func testInvalidLaunchRoutesAndDuplicateParametersAreRejected() throws {
        let invalid = [
            "https://livecontainer-launch?bundle-name=Pomodoro.app",
            "pomodoro://livecontainer-launch?bundle-name=Pomodoro.app",
            "livecontainer://other?bundle-name=Pomodoro.app",
            "livecontainer://livecontainer-launch", "livecontainer://livecontainer-launch?bundle-name=",
            "livecontainer://livecontainer-launch?bundle-name=ui",
            "livecontainer://livecontainer-launch?bundle-name=%20%20",
            "livecontainer://livecontainer-launch?bundle-name=A&bundle-name=B",
            "livecontainer://livecontainer-launch?bundle-name=A&container-folder-name=one&container-folder-name=two",
            "livecontainer://livecontainer-launch?bundle-name=A&jit=true&jit=false",
            "livecontainer://livecontainer-launch?bundle-name=A&open-url=one&open-url=two",
            "livecontainer://livecontainer-launch/extra?bundle-name=A",
            "livecontainer://user@livecontainer-launch?bundle-name=A",
            "livecontainer://livecontainer-launch:80?bundle-name=A",
            "livecontainer://livecontainer-launch?bundle-name=A#fragment"
        ]
        for text in invalid {
            XCTAssertThrowsError(try LiveContainerLaunchURL(XCTUnwrap(URL(string: text))), text)
        }
    }

    private func forwardedGuest(_ url: URL) throws -> String {
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let encoded = try XCTUnwrap(items.first { $0.name == "open-url" }?.value)
        return try XCTUnwrap(String(data: XCTUnwrap(Data(base64Encoded: encoded)), encoding: .utf8))
    }
}
