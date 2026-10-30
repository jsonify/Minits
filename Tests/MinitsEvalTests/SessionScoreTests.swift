import XCTest

final class SessionScoreTests: XCTestCase {
    private let truth = GroundTruth(intervals: [
        LabeledInterval(speaker: "Maria", start: 0, end: 100),
        LabeledInterval(speaker: "Dev", start: 100, end: 200),
        LabeledInterval(speaker: "Lee", start: 20, end: 28),   // talks over Maria
    ])

    private func line(_ start: Double, _ end: Double, _ speaker: String?,
                      flagged: Bool = false, confidence: Double = 0.5) -> LineUnderTest {
        LineUnderTest(start: start, end: end, text: "x", speaker: speaker, needsReview: flagged, confidence: confidence)
    }

    private func session(_ lines: [LineUnderTest], meetingSeconds: Double = 600) -> SessionScore {
        SessionScore(lines: Scorer.score(lines: lines, truth: truth), meetingSeconds: meetingSeconds)
    }

    // MARK: Breakdowns

    func testOverlapBreakdownOnlyCountsOverlapLines() {
        // 20-30: Maria 10 s, Lee 8 s -> overlap. 40-50: Maria alone.
        let s = session([line(20, 30, "Maria"), line(40, 50, "Maria")])
        XCTAssertEqual(s.metrics.lineCount, 2)
        XCTAssertEqual(s.overlapMetrics.lineCount, 1)
    }

    func testShortLineBreakdownCoversLinesUnderOneSecond() {
        let s = session([line(40, 40.5, "Maria"), line(41, 42, "Maria"), line(43, 50, "Maria")])
        XCTAssertEqual(s.shortLineMetrics.lineCount, 1)
    }

    // MARK: Confusion matrix

    func testConfusionMatrixCountsTrueBySpeakerAttributed() {
        let s = session([
            line(40, 50, "Maria"), line(50, 60, "Maria"), line(60, 70, "Dev"),
            line(110, 120, nil),
        ])
        XCTAssertEqual(s.confusion["Maria"]?["Maria"], 2)
        XCTAssertEqual(s.confusion["Maria"]?["Dev"], 1)
        XCTAssertEqual(s.confusion["Dev"]?[SessionScore.guestLabel], 1)
    }

    func testConfusionRowsSumToLineCountPerTrueSpeaker() {
        let s = session([line(40, 50, "Maria"), line(60, 70, "Dev"), line(110, 120, "Dev")])
        XCTAssertEqual(s.confusion["Maria"]?.values.reduce(0, +), 2)
        XCTAssertEqual(s.confusion["Dev"]?.values.reduce(0, +), 1)
    }

    // MARK: Confidence buckets

    func testConfidenceBucketsSplitAtQuarters() {
        let s = session([
            line(40, 50, "Maria", confidence: 0.0),
            line(50, 60, "Maria", confidence: 0.25),
            line(60, 70, "Maria", confidence: 0.74),
            line(70, 80, "Maria", confidence: 1.0),
        ])
        XCTAssertEqual(s.confidenceBuckets.map(\.lineCount), [1, 1, 1, 1])
    }

    func testConfidenceBucketTracksWrongAndUnflaggedErrors() {
        let s = session([
            line(40, 50, "Dev", confidence: 0.9),                  // wrong, unflagged
            line(50, 60, "Dev", flagged: true, confidence: 0.9),   // wrong, flagged
            line(60, 70, "Maria", confidence: 0.9),                // right
        ])
        let top = s.confidenceBuckets[3]
        XCTAssertEqual(top.lineCount, 3)
        XCTAssertEqual(top.wrongCount, 2)
        XCTAssertEqual(top.unflaggedErrorCount, 1)
    }

    // MARK: Pooling

    func testPoolingSumsLinesAndMeetingTime() {
        let a = session([line(40, 50, "Maria")], meetingSeconds: 600)
        let b = session([line(60, 70, "Dev", flagged: true)], meetingSeconds: 1200)
        let pooled = Scorer.pool([a, b])
        XCTAssertEqual(pooled.metrics.lineCount, 2)
        XCTAssertEqual(pooled.meetingSeconds, 1800)
    }

    func testPoolingByCountDiffersFromPoolingByDurationOnCraftedSessions() {
        // Session A: nine 1 s correct lines. Session B: one 9 s wrong unflagged line.
        let a = session((0..<9).map { line(40 + Double($0), 41 + Double($0), "Maria") })
        let b = session([line(150, 159, "Maria")])
        let pooled = Scorer.pool([a, b]).metrics
        XCTAssertEqual(pooled.unflaggedErrorRate, 0.1, accuracy: 1e-9)
        XCTAssertEqual(pooled.unflaggedErrorRateByDuration, 0.5, accuracy: 1e-9)
    }
}
