import XCTest

final class SessionCheckTests: XCTestCase {
    /// A session with nothing wrong: two members, 16-minute table, 10 s samples, clap in every track.
    private func complete() -> SessionInventory {
        SessionInventory(
            config: SessionConfig(venue: "pub", members: ["Maria", "Dev"]),
            tableSeconds: 16 * 60,
            enrollSeconds: ["Maria": 10, "Dev": 11],
            trackSeconds: ["Maria": 16 * 60, "Dev": 16 * 60 - 5],
            clapOffsets: ["Maria": 0.1, "Dev": 0.42])
    }

    private func messages(_ inventory: SessionInventory, _ severity: SessionFinding.Severity) -> [String] {
        SessionCheck.findings(for: inventory).filter { $0.severity == severity }.map(\.message)
    }

    func testCompleteSessionHasNoFindings() {
        XCTAssertEqual(SessionCheck.findings(for: complete()), [])
    }

    func testMissingTableStopsTheCheck() {
        var inventory = complete()
        inventory.tableSeconds = nil
        XCTAssertEqual(messages(inventory, .problem), ["No table.wav (the shared phone's recording)."])
    }

    func testMissingFilesForAMemberAreProblems() {
        var inventory = complete()
        inventory.enrollSeconds["Dev"] = nil
        inventory.trackSeconds["Dev"] = nil
        let problems = messages(inventory, .problem)
        XCTAssertEqual(problems.count, 2)
        XCTAssertTrue(problems.contains("No enroll/Dev.wav."))
        XCTAssertTrue(problems[1].hasPrefix("No tracks/Dev.wav"))
    }

    func testMisspelledFileNameIsAProblem() {
        var inventory = complete()
        inventory.enrollSeconds["maria"] = inventory.enrollSeconds.removeValue(forKey: "Maria")
        let problems = messages(inventory, .problem)
        XCTAssertTrue(problems.contains("No enroll/Maria.wav."))
        XCTAssertTrue(problems.contains { $0.hasPrefix("enroll/maria.wav doesn't match a member") })
    }

    func testUnconvertedAudioGetsAConvertCommand() {
        var inventory = complete()
        inventory.unconvertedAudio = ["tracks/Lee.m4a"]
        let problem = messages(inventory, .problem).first ?? ""
        XCTAssertTrue(problem.contains("afconvert -f WAVE -d LEI16@16000 -c 1 \"tracks/Lee.m4a\" \"tracks/Lee.wav\""), problem)
    }

    func testEnrollmentLengthMatchesTheApp() {
        var inventory = complete()
        inventory.enrollSeconds = ["Maria": 3, "Dev": 20]
        XCTAssertEqual(messages(inventory, .problem).count, 1)
        XCTAssertTrue(messages(inventory, .problem)[0].hasPrefix("enroll/Maria.wav is 3.0 s"))
        XCTAssertTrue(messages(inventory, .warning)[0].hasPrefix("enroll/Dev.wav is 20.0 s"))
    }

    func testShortTableAndShortTrackWarn() {
        var inventory = complete()
        inventory.tableSeconds = 5 * 60
        inventory.trackSeconds["Dev"] = 60
        let warnings = messages(inventory, .warning)
        XCTAssertEqual(warnings.count, 2)
        XCTAssertTrue(warnings[0].hasPrefix("table.wav is 5:00"))
        XCTAssertTrue(warnings[1].hasPrefix("tracks/Dev.wav is 1:00"))
    }

    func testMissingClapWarnsUnlessOffsetIsSet() {
        var inventory = complete()
        inventory.clapOffsets["Dev"] = nil
        XCTAssertEqual(messages(inventory, .warning).count, 1)
        inventory.config.trackOffsetsSeconds["Dev"] = 0.5
        XCTAssertEqual(messages(inventory, .warning), [])
    }

    func testNoMembersListedFallsBackToFileNames() {
        var inventory = complete()
        inventory.config.members = []
        XCTAssertEqual(messages(inventory, .problem), [])
        XCTAssertEqual(messages(inventory, .warning).count, 1)
    }
}
