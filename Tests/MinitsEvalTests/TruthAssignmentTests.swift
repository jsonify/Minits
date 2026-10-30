import XCTest

final class TruthAssignmentTests: XCTestCase {
    private func line(_ start: Double, _ end: Double) -> LineUnderTest {
        LineUnderTest(start: start, end: end, text: "x", speaker: nil, needsReview: false, confidence: 1)
    }

    private let truth = GroundTruth(
        intervals: [
            LabeledInterval(speaker: "Maria", start: 0, end: 10),
            LabeledInterval(speaker: "Dev", start: 10, end: 20),
        ],
        nonMemberSpans: [TimeSpan(start: 30, end: 40)])

    func testLineInsideOneIntervalGetsThatSpeaker() {
        XCTAssertEqual(Scorer.truth(for: line(2, 8), in: truth), .member("Maria", overlapping: false))
    }

    func testLineSplitSixtyFortyGetsTheLargerSpeakerAndIsOverlap() {
        // 4-10 is Maria (6 s), 10-14 is Dev (4 s): both are over 30% of the 10 s line.
        XCTAssertEqual(Scorer.truth(for: line(4, 14), in: truth), .member("Maria", overlapping: true))
    }

    func testLineWithSmallSpillIntoNextSpeakerIsNotOverlap() {
        // 8-10.5: Maria 2 s, Dev 0.5 s (20%).
        XCTAssertEqual(Scorer.truth(for: line(8, 10.5), in: truth), .member("Maria", overlapping: false))
    }

    func testLineInsideNonMemberSpanIsNonMember() {
        XCTAssertEqual(Scorer.truth(for: line(31, 35), in: truth), .nonMember)
    }

    func testLineWithNoLabeledSpeakerIsNonMember() {
        XCTAssertEqual(Scorer.truth(for: line(50, 55), in: truth), .nonMember)
    }

    func testOverlappingIntervalsOfDifferentSpeakersMarkOverlap() {
        let crosstalk = GroundTruth(intervals: [
            LabeledInterval(speaker: "Sam", start: 0, end: 10),
            LabeledInterval(speaker: "Lee", start: 2, end: 9),
        ])
        XCTAssertEqual(Scorer.truth(for: line(0, 10), in: crosstalk), .member("Sam", overlapping: true))
    }

    func testTieBreaksAlphabeticallyForDeterminism() {
        let tied = GroundTruth(intervals: [
            LabeledInterval(speaker: "Zed", start: 0, end: 5),
            LabeledInterval(speaker: "Amy", start: 5, end: 10),
        ])
        XCTAssertEqual(Scorer.truth(for: line(0, 10), in: tied), .member("Amy", overlapping: true))
    }

    func testZeroLengthLineHasNoTruth() {
        XCTAssertNil(Scorer.truth(for: line(5, 5), in: truth))
    }
}
