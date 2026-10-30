import XCTest

final class SpotCheckTests: XCTestCase {
    /// `count` two-second intervals, one every 10 s, alternating speakers.
    private func truth(_ count: Int) -> GroundTruth {
        GroundTruth(intervals: (0..<count).map { i in
            LabeledInterval(speaker: i.isMultiple(of: 2) ? "Maria" : "Dev", start: Double(i) * 10, end: Double(i) * 10 + 2)
        })
    }

    func testPicksEvenlyAcrossTheSession() {
        let clips = SpotCheck.clips(from: truth(100), count: 20)
        XCTAssertEqual(clips.count, 20)
        XCTAssertEqual(clips.map(\.number), Array(1...20))
        // Middle of each five-interval slice: indices 2, 7, 12, … 97.
        XCTAssertEqual(clips.first?.interval.start, 20)
        XCTAssertEqual(clips.last?.interval.start, 970)
    }

    func testSameLabelsGiveSameClips() {
        XCTAssertEqual(SpotCheck.clips(from: truth(57)), SpotCheck.clips(from: truth(57)))
    }

    func testFewerIntervalsThanCountTakesThemAll() {
        XCTAssertEqual(SpotCheck.clips(from: truth(7), count: 20).count, 7)
        XCTAssertEqual(SpotCheck.clips(from: GroundTruth(intervals: [])), [])
    }

    func testSkipsIntervalsTooShortToJudge() {
        let truth = GroundTruth(intervals: [
            LabeledInterval(speaker: "Maria", start: 0, end: 0.5),
            LabeledInterval(speaker: "Dev", start: 5, end: 7),
        ])
        XCTAssertEqual(SpotCheck.clips(from: truth).map(\.interval.speaker), ["Dev"])
    }

    func testClipIsPaddedAndCapped() {
        let truth = GroundTruth(intervals: [
            LabeledInterval(speaker: "Maria", start: 0.1, end: 2),
            LabeledInterval(speaker: "Dev", start: 100, end: 160),
        ])
        let clips = SpotCheck.clips(from: truth)
        XCTAssertEqual(clips[0].span.start, 0)
        XCTAssertEqual(clips[0].span.end, 2.3, accuracy: 1e-9)
        XCTAssertEqual(clips[1].span.start, 99.7, accuracy: 1e-9)
        XCTAssertEqual(clips[1].span.duration, SpotCheck.maxClipSeconds, accuracy: 1e-9)
    }

    func testOverlapAndFileName() {
        let truth = GroundTruth(intervals: [
            LabeledInterval(speaker: "Maria", start: 125, end: 130),
            LabeledInterval(speaker: "Dev", start: 128, end: 131),
        ])
        let clip = SpotCheck.clips(from: truth, count: 2)[0]
        XCTAssertEqual(clip.overlapping, ["Dev"])
        XCTAssertEqual(clip.fileName, "01-Maria-0205.wav")
    }

    func testChecklistStatesTheBar() {
        let text = SpotCheck.checklist(session: "2026-11-02-pub", clips: SpotCheck.clips(from: truth(40)))
        XCTAssertTrue(text.contains("at least 19 of 20 correct"))
        XCTAssertTrue(text.contains("| 1 | 01-Dev-0010.wav | 0:10–0:12 | Dev |  |  |  |"), text)
        XCTAssertTrue(text.hasSuffix("Correct: __ / 20\n"))
    }
}
