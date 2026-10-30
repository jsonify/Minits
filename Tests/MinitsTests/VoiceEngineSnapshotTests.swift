import XCTest

/// Guards that the `VoiceTuning` refactor (issue #1) didn't change `VoiceEngine.process()`'s
/// output with default tuning. Runs the real FluidAudio diarizer + ASR pipeline, so it needs
/// network once (model download) and does not run on Macs without a Neural Engine.
///
/// To (re)record the golden snapshot after an intentional engine change, delete
/// `Fixtures/meeting-snapshot.json`, run once with `TEST_RUNNER_RECORD_SNAPSHOT=1` set (xcodebuild
/// only forwards `TEST_RUNNER_`-prefixed variables to the test process), inspect it, and commit it.
final class VoiceEngineSnapshotTests: XCTestCase {
    /// Mirrors `ProcessedLine` for comparison and JSON snapshotting without changing app code.
    private struct SnapshotLine: Codable, Equatable {
        var start: Double
        var end: Double
        var text: String
        var speakerName: String
        var speakerID: String?
        var alternateSpeakerID: String?
        var confidence: Double
        var needsReview: Bool
        var reviewNote: String?

        init(_ line: ProcessedLine) {
            start = line.start
            end = line.end
            text = line.text
            speakerName = line.speakerName
            speakerID = line.speakerID?.uuidString
            alternateSpeakerID = line.alternateSpeakerID?.uuidString
            confidence = line.confidence
            needsReview = line.needsReview
            reviewNote = line.reviewNote
        }
    }

    private var fixturesDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    }

    private var snapshotURL: URL { fixturesDir.appendingPathComponent("meeting-snapshot.json") }

    func testProcessWithDefaultTuningMatchesSnapshot() async throws {
        let enrollURL = fixturesDir.appendingPathComponent("enroll.wav")
        let meetingURL = fixturesDir.appendingPathComponent("meeting.wav")
        guard FileManager.default.fileExists(atPath: enrollURL.path),
              FileManager.default.fileExists(atPath: meetingURL.path) else {
            throw XCTSkip("Fixture audio missing at \(fixturesDir.path)")
        }

        let engine = VoiceEngine() // default VoiceTuning()
        try await engine.prepare()
        let embedding = try await engine.voiceprint(forSampleAt: enrollURL)
        let voice = EnrolledVoice(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                   name: "Alex", embedding: embedding)

        let lines = try await engine.process(meetingAt: meetingURL, voices: [voice]) { _ in }
        let snapshot = lines.map(SnapshotLine.init)

        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            if ProcessInfo.processInfo.environment["RECORD_SNAPSHOT"] == "1" {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(snapshot).write(to: snapshotURL)
                XCTFail("Recorded snapshot to \(snapshotURL.path) — inspect it, then rerun without RECORD_SNAPSHOT.")
            } else {
                throw XCTSkip(
                    "No golden snapshot at \(snapshotURL.path). Run once with TEST_RUNNER_RECORD_SNAPSHOT=1 on an " +
                    "Apple Silicon Mac, inspect the output, and commit it.")
            }
            return
        }

        let golden = try JSONDecoder().decode([SnapshotLine].self, from: Data(contentsOf: snapshotURL))
        XCTAssertEqual(snapshot, golden, "process() with VoiceTuning() changed output vs the pre-refactor snapshot")
    }
}
