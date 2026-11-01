@testable import Minits
import SwiftData
import XCTest

/// Avatar colours (#23), editing a member and deleting a meeting (#21). These live in the app-hosted target because
/// it's the one CI runs with the app's models.
@MainActor
final class MemberAndMeetingEditTests: XCTestCase {
    /// Held so the store outlives each test's context.
    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let container = try ScreenFixtures.emptyContainer()
        self.container = container
        return ModelContext(container)
    }

    private func member(_ name: String, color: Int?, in context: ModelContext) -> Member {
        let member = Member(name: name, role: "")
        member.colorIndex = color
        context.insert(member)
        return member
    }

    func testNextColorIsTheFirstNoOneHas() throws {
        let context = try makeContext()
        let members = [0, 1, 3].map { member("M\($0)", color: $0, in: context) }
        XCTAssertEqual(Member.nextColor(among: members), 2)
        XCTAssertEqual(Member.nextColor(among: []), 0)
    }

    func testNextColorWrapsToTheLeastUsed() throws {
        let context = try makeContext()
        var members = (0..<Member.colorCount).map { member("M\($0)", color: $0, in: context) }
        members.append(member("Extra", color: 0, in: context))
        XCTAssertEqual(Member.nextColor(among: members), 1)
    }

    func testRemovingAMemberKeepsEveryoneElsesColor() throws {
        let context = try makeContext()
        let members = ["A", "B", "C"].enumerated().map { index, name in
            member(name, color: Member.nextColor(among: []) + index, in: context)
        }
        let before = members[2].colorIndex
        context.delete(members[1])
        XCTAssertEqual(members[2].colorIndex, before)
        XCTAssertEqual(Member.nextColor(among: [members[0], members[2]]), 1, "B's colour is free again")
    }

    func testFillInColorsKeepsTheColorTheListGaveThem() throws {
        let context = try makeContext()
        let members = [member("A", color: nil, in: context), member("B", color: 5, in: context),
                       member("C", color: nil, in: context)]
        XCTAssertTrue(Member.fillInColors(members))
        XCTAssertEqual(members.map(\.colorIndex), [0, 5, 2])
        XCTAssertFalse(Member.fillInColors(members), "nothing left to fill in")
    }

    func testUpdateRenamesPastLinesOnlyWhenAsked() throws {
        let context = try makeContext()
        let dev = member("Dev Patel", color: 0, in: context)
        let other = member("Maria Lopez", color: 1, in: context)
        let meeting = Meeting(title: "Board", attendeeIDs: [dev.id, other.id])
        context.insert(meeting)
        let theirs = TranscriptLine(start: 0, end: 1, text: "Hi")
        theirs.speakerID = dev.id
        theirs.speakerName = dev.name
        let guest = TranscriptLine(start: 1, end: 2, text: "Hello")
        guest.speakerName = "Guest 1"
        meeting.lines = [theirs, guest]
        try context.save()

        dev.update(name: "Devin Patel", role: "Treasurer", updatingTranscripts: false, in: context)
        XCTAssertEqual(dev.name, "Devin Patel")
        XCTAssertEqual(dev.role, "Treasurer")
        XCTAssertEqual(theirs.speakerName, "Dev Patel", "past transcripts keep the old name unless asked")

        dev.update(name: "Dev P.", role: "Treasurer", updatingTranscripts: true, in: context)
        XCTAssertEqual(theirs.speakerName, "Dev P.")
        XCTAssertEqual(guest.speakerName, "Guest 1", "other speakers' lines are untouched")
    }

    func testUpdateKeepsTheVoice() throws {
        let context = try makeContext()
        let dev = member("Dev Patel", color: 0, in: context)
        dev.embedding = [0.1, 0.2, 0.3]
        dev.update(name: "Devin Patel", role: "", updatingTranscripts: true, in: context)
        XCTAssertEqual(dev.embedding, [0.1, 0.2, 0.3])
    }

    func testDeletingAMeetingRemovesItsLinesAndRecording() throws {
        let context = try makeContext()
        let meeting = Meeting(title: "Board", attendeeIDs: [])
        context.insert(meeting)
        meeting.lines = [TranscriptLine(start: 0, end: 1, text: "Hi")]
        try context.save()
        try Data([1, 2, 3]).write(to: meeting.audioURL)

        meeting.delete(from: context)

        XCTAssertFalse(FileManager.default.fileExists(atPath: meeting.audioURL.path))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Meeting>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TranscriptLine>()), 0)
    }
}
