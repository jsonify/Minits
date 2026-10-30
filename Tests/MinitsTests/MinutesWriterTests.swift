import XCTest

/// The outline written when Apple Intelligence isn't available. The model-written path can't run in tests.
final class MinutesWriterTests: XCTestCase {
    private func input(_ kind: MeetingKind, lines: [(Double, String, String)], marks: [Double] = [],
                       attendees: [(name: String, role: String)] = []) -> MinutesInput {
        MinutesInput(kind: kind, title: "Planning chat", date: Date(timeIntervalSince1970: 0), duration: 120,
                     attendees: attendees,
                     lines: lines.map { .init(time: $0.0, speaker: $0.1, text: $0.2) },
                     motionMarks: marks)
    }

    private let chat: [(Double, String, String)] = [
        (0, "Maria", "So the fundraiser venue fell through."),
        (12, "Guest 1", "We could use the library hall instead."),
        (25, "Maria", "Okay, agreed, let's go with the library."),
        (40, "Guest 1", "I’ll call them tomorrow to book it."),
        (55, "Maria", "Can you also send the flyer draft?"),
        (70, "Guest 1", "The weather has been strange lately."),
    ]

    func testSummaryOutlineListsDecisionsActionsAndTranscript() {
        let text = MinutesWriter.outline(input(.adHoc, lines: chat))
        XCTAssertTrue(text.hasPrefix("SUMMARY — PLANNING CHAT"))
        XCTAssertTrue(text.contains("People: Maria, Guest 1"), "falls back to who spoke")
        XCTAssertTrue(text.contains("POSSIBLE DECISIONS\n• [0:25] Maria: Okay, agreed, let's go with the library.\n"))
        XCTAssertTrue(text.contains("POSSIBLE ACTION ITEMS\n• [0:40] Guest 1: I’ll call them tomorrow to book it.\n• [0:55] Maria: Can you also send the flyer draft?\n"))
        XCTAssertTrue(text.contains("TRANSCRIPT\n[0:00] Maria: So the fundraiser venue fell through."))
        XCTAssertTrue(text.contains("[1:10] Guest 1: The weather has been strange lately."))
        XCTAssertFalse(text.contains("MINUTES"))
    }

    func testSummaryOutlineQuotesMarkedMoments() {
        let text = MinutesWriter.outline(input(.adHoc, lines: chat, marks: [30]))
        XCTAssertTrue(text.contains("MARKED MOMENTS\n1. At 0:30:\n   • Maria: So the fundraiser venue fell through.\n"))
    }

    func testCuesMatchWholeWordsOnly() {
        let lines = [MinutesInput.Line(time: 0, speaker: "Dev", text: "The disagreed-upon items stay."),
                     MinutesInput.Line(time: 1, speaker: "Dev", text: "Sounds good to me.")]
        // "disagreed" isn't "agreed"; punctuation around a cue doesn't hide it.
        XCTAssertEqual(MinutesWriter.candidates(in: lines, cues: MinutesWriter.decisionCues).map(\.time), [1])
    }

    func testCandidatesAreCapped() {
        let lines = (0..<30).map { MinutesInput.Line(time: Double($0), speaker: "Dev", text: "I will do item \($0).") }
        XCTAssertEqual(MinutesWriter.candidates(in: lines, cues: MinutesWriter.actionCues).count, MinutesWriter.maxCandidates)
    }

    func testEmptyTranscriptSaysSo() {
        XCTAssertTrue(MinutesWriter.outline(input(.adHoc, lines: [])).contains(MinutesWriter.noSpeech))
        XCTAssertTrue(MinutesWriter.outline(input(.board, lines: [])).contains(MinutesWriter.noSpeech))
    }

    func testBoardOutlineKeepsMinutesShapeAndSuggestsActions() {
        let text = MinutesWriter.outline(input(.board, lines: chat, attendees: [("Maria Lopez", "Chair")]))
        XCTAssertTrue(text.hasPrefix("MINUTES — PLANNING CHAT"))
        XCTAssertTrue(text.contains("Present: Maria Lopez (Chair)"))
        XCTAssertTrue(text.contains("ACTION ITEMS\nPossible action items from the transcript:\n• [0:40] Guest 1:"))
        XCTAssertTrue(text.contains("ADJOURNMENT"))
    }

    func testPromptsDifferByKind() {
        XCTAssertTrue(MinutesWriter.Prompts.document(for: .adHoc).contains("Action Items"))
        XCTAssertTrue(MinutesWriter.Prompts.document(for: .board).contains("Call to Order"))
        XCTAssertFalse(MinutesWriter.Prompts.notes(for: .board).contains("No business"),
                       "a part with no motions must still say what was discussed")
    }

    func testMeetingKindDefaultsToBoard() {
        XCTAssertEqual(MeetingKind(rawValue: "adHoc"), .adHoc)
        XCTAssertEqual(Meeting(title: "Old", attendeeIDs: []).kind, .board)
    }
}
