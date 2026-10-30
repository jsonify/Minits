import XCTest

final class ReportTests: XCTestCase {
    private let tuning = TuningReport(acceptSimilarity: 0.40, sureSimilarity: 0.50, minimumMargin: 0.06, overrideGap: 0.10)
    private let truth = GroundTruth(intervals: [
        LabeledInterval(speaker: "Maria", start: 0, end: 100),
        LabeledInterval(speaker: "Dev", start: 100, end: 200),
    ])

    private func line(_ start: Double, _ end: Double, _ speaker: String?, flagged: Bool = false) -> LineUnderTest {
        LineUnderTest(start: start, end: end, text: "line at \(Int(start))", speaker: speaker,
                      needsReview: flagged, confidence: 0.7)
    }

    private func report(_ lines: [LineUnderTest], tuning: TuningReport? = nil) -> EvalReport {
        let score = SessionScore(lines: Scorer.score(lines: lines, truth: truth), meetingSeconds: 600)
        return EvalReport(tuning: tuning ?? self.tuning, fluidAudioVersion: "0.18.0",
                          sessions: [("2026-11-02-pub", score)])
    }

    private let lines = [
        LineUnderTest(start: 10, end: 20, text: "a", speaker: "Maria", needsReview: false, confidence: 0.8),
        LineUnderTest(start: 110, end: 120, text: "b", speaker: "Maria", needsReview: false, confidence: 0.6),
        LineUnderTest(start: 130, end: 140, text: "c", speaker: "Maria", needsReview: true, confidence: 0.2),
    ]

    func testSameInputsGiveIdenticalBytes() throws {
        XCTAssertEqual(try report(lines).encoded(), try report(lines).encoded())
    }

    func testKeysAreSorted() throws {
        let json = String(decoding: try report(lines).encoded(), as: UTF8.self)
        let fluid = try XCTUnwrap(json.range(of: "\"fluidAudioVersion\""))
        let overall = try XCTUnwrap(json.range(of: "\"overall\""))
        let tuningKey = try XCTUnwrap(json.range(of: "\"tuning\""))
        XCTAssertLessThan(fluid.lowerBound, overall.lowerBound)
        XCTAssertLessThan(overall.lowerBound, tuningKey.lowerBound)
    }

    func testRoundTripsThroughJSON() throws {
        let original = report(lines)
        XCTAssertEqual(try EvalReport.decode(original.encoded()), original)
    }

    func testListsEveryWrongUnflaggedLine() {
        let errors = report(lines).unflaggedErrors
        XCTAssertEqual(errors, [UnflaggedErrorLine(session: "2026-11-02-pub", start: 110, text: "b",
                                                   truth: "Dev", got: "Maria", score: 0.6)])
    }

    func testUnflaggedErrorEncodesTrueKey() throws {
        let json = String(decoding: try report(lines).encoded(), as: UTF8.self)
        XCTAssertTrue(json.contains("\"true\" : \"Dev\""))
    }

    func testRecordsTuning() {
        var changed = tuning
        changed.sureSimilarity = 0.60
        XCTAssertEqual(report(lines, tuning: changed).tuning.sureSimilarity, 0.60)
    }

    func testTableMentionsSessionsAndErrors() {
        let table = report(lines).table()
        XCTAssertTrue(table.contains("2026-11-02-pub"))
        XCTAssertTrue(table.contains("overall"))
        XCTAssertTrue(table.contains("true Dev, got Maria"))
        XCTAssertTrue(table.contains("0:01:50"))
    }

    // MARK: compare

    func testCompareIdenticalReportsHasZeroDeltas() {
        let deltas = ReportComparison.deltas(from: report(lines), to: report(lines))
        XCTAssertFalse(deltas.isEmpty)
        for d in deltas where d.delta != nil { XCTAssertEqual(d.delta, 0) }
    }

    func testCompareShowsSignedDeltas() throws {
        var fixed = lines
        fixed[1].speaker = "Dev"
        let deltas = ReportComparison.deltas(from: report(lines), to: report(fixed))
        let accuracy = try XCTUnwrap(deltas.first { $0.label == "overall accuracy" })
        XCTAssertEqual(accuracy.delta ?? .nan, 1.0 / 3.0, accuracy: 1e-9)
        let unflagged = try XCTUnwrap(deltas.first { $0.label == "overall unflaggedErrorRate" })
        XCTAssertEqual(unflagged.delta ?? .nan, -1.0 / 3.0, accuracy: 1e-9)
        XCTAssertTrue(ReportComparison.render(deltas).contains("+0.3333"))
    }
}
