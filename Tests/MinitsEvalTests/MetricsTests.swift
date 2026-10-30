import XCTest

final class MetricsTests: XCTestCase {
    private let truth = GroundTruth(
        intervals: [
            LabeledInterval(speaker: "Maria", start: 0, end: 100),
            LabeledInterval(speaker: "Dev", start: 100, end: 200),
        ],
        nonMemberSpans: [TimeSpan(start: 300, end: 400)])

    private func line(_ start: Double, _ end: Double, _ speaker: String?, flagged: Bool = false) -> LineUnderTest {
        LineUnderTest(start: start, end: end, text: "x", speaker: speaker, needsReview: flagged, confidence: 0.5)
    }

    private func metrics(_ lines: [LineUnderTest], meetingSeconds: Double = 600) -> Metrics {
        Metrics(lines: Scorer.score(lines: lines, truth: truth), meetingSeconds: meetingSeconds)
    }

    // MARK: Correctness

    func testMemberLineIsCorrectOnlyForTheRightMember() {
        let scored = Scorer.score(lines: [line(10, 20, "Maria"), line(30, 40, "Dev")], truth: truth)
        XCTAssertEqual(scored.map(\.correct), [true, false])
    }

    func testGuestOnNonMemberSpanIsCorrectButMemberThereIsWrong() {
        let scored = Scorer.score(lines: [line(310, 320, nil), line(330, 340, "Maria")], truth: truth)
        XCTAssertEqual(scored.map(\.correct), [true, false])
    }

    func testGuestOnMemberSpeechIsWrong() {
        XCTAssertEqual(Scorer.score(lines: [line(10, 20, nil)], truth: truth).map(\.correct), [false])
    }

    func testZeroLengthLinesAreNotScored() {
        XCTAssertTrue(Scorer.score(lines: [line(10, 10, "Maria")], truth: truth).isEmpty)
    }

    // MARK: Rates

    func testAccuracyAndUnflaggedErrorRate() {
        // 4 lines: 2 right, 1 wrong+flagged, 1 wrong+unflagged.
        let m = metrics([
            line(0, 10, "Maria"), line(10, 20, "Maria"),
            line(20, 30, "Dev", flagged: true), line(30, 40, "Dev"),
        ])
        XCTAssertEqual(m.accuracy, 0.5, accuracy: 1e-9)
        XCTAssertEqual(m.unflaggedErrorRate, 0.25, accuracy: 1e-9)
        XCTAssertEqual(m.flaggedRate, 0.25, accuracy: 1e-9)
    }

    func testFlagRecallIsOneWhenEveryWrongLineIsFlagged() {
        let m = metrics([line(0, 10, "Dev", flagged: true), line(10, 20, "Maria")])
        XCTAssertEqual(m.flagRecall, 1.0)
    }

    func testFlagRecallIsHalfWhenOneOfTwoWrongLinesIsFlagged() {
        let m = metrics([line(0, 10, "Dev", flagged: true), line(10, 20, "Dev")])
        XCTAssertEqual(m.flagRecall, 0.5)
    }

    func testFlagRecallIsNilWithNoWrongLines() {
        XCTAssertNil(metrics([line(0, 10, "Maria")]).flagRecall)
    }

    func testEmptyInputGivesZeroRatesNotNaN() {
        let m = metrics([])
        XCTAssertEqual(m.accuracy, 0)
        XCTAssertEqual(m.unflaggedErrorRate, 0)
        XCTAssertEqual(m.flaggedRate, 0)
        XCTAssertEqual(m.reviewMinutesPerHour, 0)
    }

    func testDurationWeightedRatesDifferFromLineWeighted() {
        // One short correct line, one long wrong unflagged line.
        let m = metrics([line(0, 1, "Maria"), line(10, 19, "Dev")])
        XCTAssertEqual(m.unflaggedErrorRate, 0.5, accuracy: 1e-9)
        XCTAssertEqual(m.unflaggedErrorRateByDuration, 0.9, accuracy: 1e-9)
    }

    // MARK: Review burden

    func testReviewBurdenWorkedExample() {
        // Ten 5 s flagged lines in a 10 minute meeting: (50 s listening + 40 s deciding) = 90 s,
        // scaled to an hour is 540 s = 9.0 minutes.
        let lines = (0..<10).map { line(Double($0) * 10, Double($0) * 10 + 5, "Maria", flagged: true) }
        XCTAssertEqual(metrics(lines, meetingSeconds: 600).reviewMinutesPerHour, 9.0, accuracy: 1e-9)
    }

    func testUnflaggedLinesCostNoReviewTime() {
        XCTAssertEqual(metrics([line(0, 10, "Maria")]).reviewMinutesPerHour, 0)
    }
}
