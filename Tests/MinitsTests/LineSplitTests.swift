import SwiftData
import XCTest

final class LineSplitTests: XCTestCase {
    private let text = "anything there? Oh, yeah, um,"
    private let starts: [Double] = [22.1, 22.6, 23.4, 23.8, 24.3]

    func testWords() {
        XCTAssertEqual(LineSplit.words("  anything  there?\nOh "), ["anything", "there?", "Oh"])
    }

    func testSplitsAtTheWordsOwnTime() throws {
        let halves = try XCTUnwrap(LineSplit.halves(text: text, start: 22, end: 25, wordStarts: starts, at: 2))
        XCTAssertEqual(halves.firstText, "anything there?")
        XCTAssertEqual(halves.secondText, "Oh, yeah, um,")
        XCTAssertEqual(halves.time, 23.4, accuracy: 1e-9)
        XCTAssertEqual(halves.firstWordStarts, [22.1, 22.6])
        XCTAssertEqual(halves.secondWordStarts, [23.4, 23.8, 24.3])
        XCTAssertTrue(halves.isExact)
    }

    func testEstimatesTheTimeWithoutWordTimings() throws {
        // "anything" + "there?" is 14 of 25 letters, so 14/25 of the way through 22–25.
        let halves = try XCTUnwrap(LineSplit.halves(text: text, start: 22, end: 25, wordStarts: [], at: 2))
        XCTAssertEqual(halves.time, 22 + 3 * 14.0 / 25.0, accuracy: 1e-9)
        XCTAssertEqual(halves.firstWordStarts, [])
        XCTAssertEqual(halves.secondWordStarts, [])
        XCTAssertFalse(halves.isExact)
    }

    func testMismatchedTimingsAreEstimated() throws {
        let halves = try XCTUnwrap(LineSplit.halves(text: text, start: 22, end: 25, wordStarts: [22.1], at: 2))
        XCTAssertFalse(halves.isExact)
    }

    func testEachSideKeepsAWord() {
        XCTAssertNil(LineSplit.halves(text: text, start: 22, end: 25, wordStarts: starts, at: 0))
        XCTAssertNil(LineSplit.halves(text: text, start: 22, end: 25, wordStarts: starts, at: 5))
        XCTAssertNil(LineSplit.halves(text: "Hello", start: 0, end: 1, wordStarts: [0], at: 1))
    }

    func testTheCutStaysInsideTheLine() throws {
        let early = try XCTUnwrap(LineSplit.halves(text: "a b", start: 10, end: 12, wordStarts: [9, 9.5], at: 1))
        XCTAssertGreaterThan(early.time, 10)
        let late = try XCTUnwrap(LineSplit.halves(text: "a b", start: 10, end: 12, wordStarts: [10, 13], at: 1))
        XCTAssertLessThan(late.time, 12)
    }

    @MainActor
    func testMeetingSplitFlagsBothHalves() throws {
        let container = try ModelContainer(for: Member.self, Meeting.self, TranscriptLine.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let meeting = Meeting(title: "Test", kind: .adHoc, attendeeIDs: [])
        context.insert(meeting)
        let kepler = UUID(), jason = UUID()
        let line = TranscriptLine(start: 22, end: 25, text: text)
        line.wordStarts = starts
        line.speakerID = kepler
        line.speakerName = "Kepler"
        line.alternateSpeakerID = jason
        line.needsReview = true
        line.reviewNote = "Two members sound alike here"
        meeting.lines = [line]
        meeting.status = .ready

        let second = try XCTUnwrap(meeting.split(line, atWord: 2))
        try context.save()

        XCTAssertEqual(meeting.sortedLines.map(\.text), ["anything there?", "Oh, yeah, um,"])
        XCTAssertEqual(line.end, 23.4, accuracy: 1e-9)
        XCTAssertEqual(second.start, 23.4, accuracy: 1e-9)
        XCTAssertEqual(second.end, 25)
        XCTAssertEqual(second.speakerID, kepler)
        XCTAssertEqual(second.alternateSpeakerID, jason)
        XCTAssertEqual(meeting.linesNeedingReview.count, 2)
        XCTAssertTrue(meeting.linesNeedingReview.allSatisfy { $0.reviewNote == LineSplit.reviewNote })
        XCTAssertEqual(meeting.status, .needsReview)
        XCTAssertNil(meeting.split(second, atWord: 0))
    }
}
