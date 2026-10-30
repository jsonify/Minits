import XCTest

final class SessionFolderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeSession(_ name: String, files: [String]) throws -> URL {
        let folder = root.appendingPathComponent(name)
        for file in files {
            let url = folder.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{\"intervals\": []}".utf8).write(to: url)
        }
        return folder
    }

    func testDiscoversSessionsSortedByName() throws {
        _ = try makeSession("b-quiet", files: ["table.wav"])
        _ = try makeSession("a-pub", files: ["table.wav"])
        _ = try makeSession("notes", files: ["readme.txt"])
        XCTAssertEqual(try SessionFolder.discover(at: root).map(\.name), ["a-pub", "b-quiet"])
    }

    func testFolderWithTableIsItselfASession() throws {
        let session = try makeSession("a-pub", files: ["table.wav"])
        XCTAssertEqual(try SessionFolder.discover(at: session).map(\.name), ["a-pub"])
    }

    func testNoSessionsIsAnError() {
        XCTAssertThrowsError(try SessionFolder.discover(at: root))
    }

    func testMissingLabelsNamesTheSession() throws {
        let session = SessionFolder(url: try makeSession("2026-11-02-pub", files: ["table.wav"]))
        XCTAssertThrowsError(try session.labels()) { error in
            XCTAssertEqual(error as? SessionFolderError, .missing(session: "2026-11-02-pub", file: "labels.json"))
            XCTAssertTrue(error.localizedDescription.contains("2026-11-02-pub"))
        }
    }

    func testLabelsWithoutNonMemberSpansDecode() throws {
        let session = SessionFolder(url: try makeSession("s", files: ["table.wav"]))
        try Data(#"{"intervals": [{"speaker": "Maria", "start": 1, "end": 2}]}"#.utf8).write(to: session.labelsURL)
        let truth = try session.labels()
        XCTAssertEqual(truth.intervals.count, 1)
        XCTAssertEqual(truth.nonMemberSpans, [])
    }

    func testEnrollmentSamplesAreNamedByFile() throws {
        let session = SessionFolder(url: try makeSession("s", files: ["table.wav", "enroll/Maria.wav", "enroll/Dev.wav"]))
        XCTAssertEqual(try session.enrollmentSamples().map(\.member), ["Dev", "Maria"])
    }

    func testConfigDefaultsWhenMissing() throws {
        let session = SessionFolder(url: try makeSession("s", files: ["table.wav"]))
        XCTAssertEqual(try session.config(), SessionConfig())
    }

    func testConfigReadsOffsets() throws {
        let session = SessionFolder(url: try makeSession("s", files: ["table.wav"]))
        try Data(#"{"venue": "pub", "members": ["Maria", "Dev"], "trackOffsetsSeconds": {"Dev": 0.42}}"#.utf8)
            .write(to: session.configURL)
        let config = try session.config()
        XCTAssertEqual(config.members, ["Maria", "Dev"])
        XCTAssertEqual(config.trackOffsetsSeconds["Dev"], 0.42)
    }
}
