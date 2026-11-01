@testable import Minits
import Foundation
import SwiftData

/// Sample data for the screenshots, in an in-memory store: four members (three with a voice) and a meeting in each
/// state the screens show.
@MainActor
struct ScreenFixtures {
    let container: ModelContainer
    let members: [Member]
    let recording: Meeting
    let processing: Meeting
    let failed: Meeting
    let review: Meeting
    let minutes: Meeting
    let summaryToWrite: Meeting

    /// A store with nothing in it, for the empty Home screen.
    static func emptyContainer() throws -> ModelContainer {
        try ModelContainer(for: Member.self, Meeting.self, TranscriptLine.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    init() throws {
        container = try Self.emptyContainer()
        let context = container.mainContext

        let people: [(String, String, Bool)] = [
            ("Maria Lopez", "Chair", true),
            ("Dev Patel", "Treasurer", true),
            ("Sam Okafor", "Secretary", true),
            ("Jo Kim", "Member", false),
        ]
        members = people.enumerated().map { index, person in
            let member = Member(name: person.0, role: person.1, sortOrder: index)
            if person.2 {
                member.embedding = (0..<256).map { Float(($0 + index * 37) % 17) / 17 }
                member.voiceSavedAt = Self.date
            }
            context.insert(member)
            return member
        }
        let present = members.prefix(3).map(\.id)

        recording = Self.meeting("October Board Meeting", .board, .recording, present, minutesAgo: 0, in: context)
        recording.motionMarks = [604, 1_810]

        processing = Self.meeting("October Board Meeting", .board, .processing, present, minutesAgo: 60, in: context)
        processing.durationSeconds = 3_725

        failed = Self.meeting("Budget Workshop", .adHoc, .failed, present, minutesAgo: 60 * 24, in: context)
        failed.durationSeconds = 1_480
        failed.errorMessage = "The voice models couldn't be loaded. Check there's space on this device and try again."

        review = Self.meeting("September Board Meeting", .board, .needsReview, present, minutesAgo: 60 * 24 * 30,
                              in: context)
        review.durationSeconds = 3_725
        review.motionMarks = [604]
        review.lines = Self.reviewLines(members)

        minutes = Self.meeting("August Board Meeting", .board, .ready, present, minutesAgo: 60 * 24 * 60, in: context)
        minutes.durationSeconds = 2_940
        minutes.lines = Self.reviewLines(members).map { line in
            line.needsReview = false
            line.reviewNote = nil
            return line
        }
        minutes.minutes = Self.minutesText

        summaryToWrite = Self.meeting("Launch Planning", .adHoc, .ready, present, minutesAgo: 60 * 24 * 2, in: context)
        summaryToWrite.durationSeconds = 1_260
        summaryToWrite.lines = Self.reviewLines(members).map { line in
            line.needsReview = false
            return line
        }

        try context.save()
    }

    /// 14 October 2026, 23:00 UTC (7 PM Eastern), so the screenshots don't change from run to run.
    static let date = Date(timeIntervalSince1970: 1_792_018_800)

    private static func meeting(_ title: String, _ kind: MeetingKind, _ status: MeetingStatus, _ attendees: [UUID],
                                minutesAgo: Double, in context: ModelContext) -> Meeting {
        let meeting = Meeting(title: title, kind: kind, attendeeIDs: attendees)
        meeting.startedAt = date.addingTimeInterval(-minutesAgo * 60)
        meeting.status = status
        context.insert(meeting)
        return meeting
    }

    /// A short stretch of a board meeting: confident lines, a close call between two members, a guest, and a motion.
    private static func reviewLines(_ members: [Member]) -> [TranscriptLine] {
        let maria = members[0], dev = members[1], sam = members[2]
        func line(_ start: Double, _ length: Double, _ text: String, _ speaker: Member?, guest: String = "Guest 1",
                  confidence: Double = 0.9, review: String? = nil, alternate: Member? = nil) -> TranscriptLine {
            let line = TranscriptLine(start: start, end: start + length, text: text)
            line.speakerID = speaker?.id
            line.speakerName = speaker?.name ?? guest
            line.confidence = confidence
            line.needsReview = review != nil
            line.reviewNote = review
            line.alternateSpeakerID = alternate?.id
            return line
        }
        return [
            line(12, 6, "Let's call the meeting to order. Everyone's here except Jo, who sent apologies.", maria),
            line(19, 9, "The treasurer's report is in your packet. We're about four hundred under budget for the quarter.",
                 dev),
            line(29, 4, "Is that before or after the roof repair?", sam, confidence: 0.46, review: "Close call",
                 alternate: dev),
            line(34, 7, "After. The repair came in at eleven hundred, a bit less than the quote.", dev),
            line(43, 5, "Sorry to interrupt, can I get anyone another round?", nil, confidence: 0.2,
                 review: "Unknown voice"),
            line(600, 8, "I move that we approve the treasurer's report as presented.", sam, confidence: 0.52,
                 review: "Close call", alternate: maria),
            line(609, 3, "Second.", dev),
            line(613, 6, "All in favour? That's carried, five to nothing.", maria),
        ]
    }

    private static let minutesText = """
    # August Board Meeting

    **Present:** Maria Lopez (Chair), Dev Patel (Treasurer), Sam Okafor (Secretary)
    **Apologies:** Jo Kim

    ## Treasurer's report
    The treasurer reported the quarter roughly $400 under budget, after the roof repair ($1,100, under the quote).

    ## Motions
    - **Motion:** to approve the treasurer's report as presented. Moved by Sam Okafor, seconded by Dev Patel. \
    Carried 5–0.

    ## Action items
    - Dev Patel: circulate the updated budget before the next meeting.
    - Sam Okafor: book the hall for the AGM.
    """
}
