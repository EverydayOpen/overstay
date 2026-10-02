import Foundation
import XCTest
@testable import OverstayCore

// Placeholder tests for the frozen Model (architect). The core owner adds the real suites beside this file.
final class ModelTests: XCTestCase {
    private func snapshot(pid: Int32 = 4242, start: Int64 = 1_800_000_000) -> ProcessSnapshot {
        ProcessSnapshot(pid: pid, ppid: 1, uid: 501, startSeconds: start, path: "/usr/local/bin/node",
                        argv: ["node", "/x/node_modules/.bin/mcp-server-fixture"], footprintBytes: 50 << 20)
    }

    func testIdentityDiffersWhenThePidIsReused() {
        XCTAssertEqual(snapshot().identity, snapshot().identity)
        XCTAssertNotEqual(snapshot().identity, snapshot(start: 1_800_000_001).identity)
        XCTAssertEqual(snapshot().name, "node")
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let original = snapshot()
        let decoded = try JSONDecoder().decode(ProcessSnapshot.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(original.age(at: Date(timeIntervalSince1970: 1_800_000_600)), 600)
        XCTAssertEqual(original.age(at: Date(timeIntervalSince1970: 1_700_000_000)), 0, "age is never negative")
    }

    func testOutcomeCountsOnlyWhatWasStopped() {
        func target(_ pid: Int32, _ mb: UInt64) -> StopTarget {
            StopTarget(identity: snapshot(pid: pid).identity, name: "node", signatureID: "mcp-server-x", agent: .unattributed,
                       projectName: "foo", approvedTier: .ghost, footprintBytes: mb << 20, depth: 0, why: "test")
        }
        let results = [TargetOutcome(target: target(10, 100), status: .stopped),
                       TargetOutcome(target: target(11, 200), status: .forceStopped),
                       TargetOutcome(target: target(12, 400), status: .survived),
                       TargetOutcome(target: target(13, 800), status: .alreadyGone),
                       TargetOutcome(target: target(14, 1600), status: .changedSinceScan)]
        let outcome = StopOutcome(batchID: "b", mode: .terminate, startedAt: Date(), finishedAt: Date(), results: results)
        XCTAssertEqual(outcome.stoppedCount, 2)
        XCTAssertEqual(outcome.heldBytes, 300 << 20)
        XCTAssertEqual(outcome.survivors.map(\.id), [12])
        XCTAssertEqual(outcome.notSentCount, 1)
    }

    func testStoredPreferencesSurviveMissingAndUnknownFields() throws {
        func decode(_ json: String) throws -> Preferences { try JSONDecoder().decode(Preferences.self, from: Data(json.utf8)) }
        XCTAssertEqual(try decode("{}"), Preferences.default)
        let mine = Preferences(ageGateMinutes: 30, confirmYoungerThanHours: 5, neverTouch: ["/a", "postgres"], notificationsEnabled: true,
                               notifyThresholdBytes: 7, shareIncludesProjectNames: true, autoScanSeconds: 0, hasSeenFirstRun: true)
        let full = try JSONSerialization.jsonObject(with: JSONEncoder().encode(mine)) as! [String: Any]
        XCTAssertEqual(full.count, 8)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(mine)), mine)
        // Dropping any one field keeps every other stored value (an upgrade that adds a field must not reset the rest).
        for key in full.keys {
            var partial = full
            partial[key] = nil
            let got = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: partial))
            var want = mine
            switch key {
            case "ageGateMinutes": want.ageGateMinutes = Preferences.default.ageGateMinutes
            case "confirmYoungerThanHours": want.confirmYoungerThanHours = Preferences.default.confirmYoungerThanHours
            case "neverTouch": want.neverTouch = []
            case "notificationsEnabled": want.notificationsEnabled = false
            case "notifyThresholdBytes": want.notifyThresholdBytes = Preferences.default.notifyThresholdBytes
            case "shareIncludesProjectNames": want.shareIncludesProjectNames = false
            case "autoScanSeconds": want.autoScanSeconds = Preferences.default.autoScanSeconds
            case "hasSeenFirstRun": want.hasSeenFirstRun = false
            default: XCTFail("unexpected key \(key)")
            }
            XCTAssertEqual(got, want, "missing \(key)")
        }
        // A removed field in an old blob is ignored.
        XCTAssertEqual(try decode(#"{"neverTouch":["x"],"someOldField":true}"#).neverTouch, ["x"])
    }

    func testPreferencesClampTheAgeGate() {
        XCTAssertEqual(Preferences(ageGateMinutes: 0).ageGateSeconds, 60)
        XCTAssertEqual(Preferences.default.ageGateSeconds, 600)
        XCTAssertEqual(Preferences(ageGateMinutes: 99_999).ageGateSeconds, 1440 * 60)
    }

    func testDemoScenarioNamesMatchTheLaunchArgument() {
        XCTAssertEqual(DemoScenario.allCases.map(\.rawValue), ["quiet", "leftovers", "maybe-only", "refused", "survivors", "first-run"])
    }
}
