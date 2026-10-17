import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class SignedAppGroupsTests: XCTestCase {
    private let configured = "group.com.example.Pomodoro.Native"
    private let team = "ABCDE12345"

    private func executable(groups: [String]? = nil, teamID: String? = "ABCDE12345") throws -> Data {
        var dictionary: [String: Any] = [:]
        if let groups { dictionary["com.apple.security.application-groups"] = groups }
        if let teamID { dictionary["com.apple.developer.team-identifier"] = teamID }
        let xml = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        var bytes = [UInt8](repeating: 0, count: 76)
        func put(_ value: Int, _ offset: Int, little: Bool = true) {
            for index in 0..<4 {
                let shift = (little ? index : 3 - index) * 8
                bytes[offset + index] = UInt8(truncatingIfNeeded: value >> shift)
            }
        }
        put(0xfeedfacf, 0); put(0x0100000c, 4)
        put(1, 16); put(16, 20)
        put(0x1d, 32); put(16, 36); put(48, 40); put(28 + xml.count, 44)
        put(0xfade0cc0, 48, little: false); put(28 + xml.count, 52, little: false)
        put(1, 56, little: false); put(5, 60, little: false); put(20, 64, little: false)
        put(0xfade7171, 68, little: false); put(8 + xml.count, 72, little: false)
        bytes.append(contentsOf: xml)
        return Data(bytes)
    }

    func testReadsExactGroupAndSideStoreTeamSuffix() throws {
        for group in [configured, configured + "." + team] {
            let permissions = try SignedAppGroups.read(from: executable(groups: [group]))
            XCTAssertEqual(permissions.groups, [group])
            XCTAssertEqual(permissions.teamID, team)
            XCTAssertEqual(try permissions.group(for: configured), group)
        }
    }

    func testExactGroupWinsWhenBothFormsAreDeclared() throws {
        let permissions = SignedAppGroups(groups: [configured + "." + team, configured], teamID: team)
        XCTAssertEqual(try permissions.group(for: configured), configured)
    }

    func testRejectsUnrelatedOrUndeclaredGroups() throws {
        for groups in [[], ["group.other"], [configured + ".OTHERTEAM"], [configured + "." + team + ".extra"]] {
            let permissions = try SignedAppGroups.read(from: executable(groups: groups))
            XCTAssertThrowsError(try permissions.group(for: configured))
        }
        let missing = try SignedAppGroups.read(from: executable())
        XCTAssertTrue(missing.groups.isEmpty)
        XCTAssertThrowsError(try missing.group(for: configured))
    }

    func testSuffixRequiresSignedTeamAndExactGroupDoesNot() throws {
        let suffixed = try SignedAppGroups.read(from: executable(groups: [configured + "." + team], teamID: nil))
        XCTAssertThrowsError(try suffixed.group(for: configured))
        let exact = try SignedAppGroups.read(from: executable(groups: [configured], teamID: nil))
        XCTAssertEqual(try exact.group(for: configured), configured)
        for configuration in ["", "group.", "not-a-group", "group.$(UNRESOLVED)"] {
            XCTAssertThrowsError(try exact.group(for: configuration))
        }
    }

    func testEveryTruncatedExecutableFailsSafely() throws {
        let data = try executable(groups: [configured])
        for length in 0..<data.count {
            XCTAssertThrowsError(try SignedAppGroups.read(from: Data(data.prefix(length))))
        }
    }

    func testRejectsMalformedCommandsSignatureAndEntitlementPayload() throws {
        let original = try executable(groups: [configured])
        // Invalid format, CPU, command table, command size, signature bounds,
        // superblob header, index bounds, blob header and property list.
        for offset in [0, 4, 16, 20, 36, 40, 44, 48, 52, 56, 64, 68, 72, 76] {
            var data = original
            data.replaceSubrange(offset..<(offset + 4), with: [255, 255, 255, 255])
            XCTAssertThrowsError(try SignedAppGroups.read(from: data), "Offset \(offset)")
        }
        var unsigned = original
        unsigned.replaceSubrange(32..<36, with: [0, 0, 0, 0])
        XCTAssertThrowsError(try SignedAppGroups.read(from: unsigned))
        var derOnly = original
        derOnly.replaceSubrange(60..<64, with: [0, 0, 0, 7])
        XCTAssertThrowsError(try SignedAppGroups.read(from: derOnly))
    }
}
