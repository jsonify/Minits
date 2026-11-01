@testable import Minits
import CoreText
import PDFKit
import XCTest

/// The PDF export: what's on the pages, how the draft's Markdown is read, and that long drafts break between lines.
final class MinutesPDFTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_792_018_800)
    private let letter = CGSize(width: 612, height: 792)

    private func pdf(_ kind: MeetingKind = .board, title: String = "October Board Meeting", body: String) -> MinutesPDF {
        MinutesPDF(kind: kind, title: title, date: date,
                   present: [.init(name: "Maria Lopez", role: "Chair"), .init(name: "Dev Patel", role: "")],
                   absent: [.init(name: "Jo Kim", role: "Member")],
                   body: body)
    }

    private func pages(_ pdf: MinutesPDF) throws -> [String] {
        let document = try XCTUnwrap(PDFDocument(data: pdf.data(pageSize: letter)), "the file opens as a PDF")
        return (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
    }

    func testBoardMeetingHasTitleDateAttendanceAndPageNumber() throws {
        let text = try pages(pdf(body: "## Motions\n- **Motion:** to approve the budget. Carried 5–0.")).joined()
        XCTAssertTrue(text.contains("October Board Meeting"))
        XCTAssertTrue(text.contains("Board meeting · "))
        XCTAssertTrue(text.contains(date.formatted(.dateTime.year())), "the date")
        XCTAssertTrue(text.contains("Present: Maria Lopez (Chair), Dev Patel"))
        XCTAssertTrue(text.contains("Absent: Jo Kim (Member)"))
        XCTAssertTrue(text.contains("Motion: to approve the budget."))
        XCTAssertFalse(text.contains("**"), "inline Markdown is drawn, not printed")
        XCTAssertFalse(text.contains("##"))
        XCTAssertTrue(text.contains("Page 1 of 1"))
    }

    func testAdHocMeetingHasNoAttendance() throws {
        let text = try pages(pdf(.adHoc, title: "Launch Planning", body: "Summary\nWe picked a date.")).joined()
        XCTAssertTrue(text.contains("Launch Planning"))
        XCTAssertTrue(text.contains("Ad-hoc meeting · "))
        XCTAssertTrue(text.contains("We picked a date."))
        XCTAssertFalse(text.contains("Absent"))
        XCTAssertFalse(text.contains("Present:"))
    }

    func testLongDraftBreaksBetweenLinesAndNumbersEveryPage() throws {
        let body = (1...240).map { "- Item \($0) of the long draft." }.joined(separator: "\n")
        let pages = try pages(pdf(body: body))
        XCTAssertGreaterThan(pages.count, 2)
        for (index, page) in pages.enumerated() {
            XCTAssertTrue(page.contains("Page \(index + 1) of \(pages.count)"), "page \(index + 1) is numbered")
        }
        // Every line is on exactly one page, whole.
        for number in 1...240 {
            let line = "Item \(number) of the long draft."
            XCTAssertEqual(pages.filter { $0.contains(line) }.count, 1, line)
        }
    }

    func testAPageNeverEndsOnAHeading() {
        let section = "## Section\n" + (1...7).map { "Paragraph \($0) about the topic at hand." }.joined(separator: "\n")
        let body = Array(repeating: section, count: 30).joined(separator: "\n\n")
        let text = pdf(body: body).attributedText()
        let frames = MinutesPDF.paginate(text, in: MinutesPDF.textRect(for: letter))
        XCTAssertGreaterThan(frames.count, 2)
        for frame in frames.dropLast() {
            let lines = (CTFrameGetLines(frame) as? [CTLine]) ?? []
            let last = CTLineGetStringRange(lines.last!).location
            XCTAssertNil(text.attribute(MinutesPDF.Style.keepWithNext, at: last, effectiveRange: nil))
        }
        // Nothing lost or repeated between frames.
        let covered = frames.map { CTFrameGetVisibleStringRange($0).length }.reduce(0, +)
        XCTAssertEqual(covered, text.length)
    }

    func testReadsTheDraftsMarkdownAndPlainHeadings() {
        let body = """
        # August Board Meeting

        **Present:** Maria Lopez (Chair)
        ## Treasurer's report
        **Old Business**
        CALL TO ORDER
        Action Items:
        - Dev: circulate the budget.
          * nested point
        2) Second motion
        12. Twelfth
           Moved by: [name]
        ---
        Respectfully submitted,
        """
        XCTAssertEqual(MinutesPDF.blocks(from: body), [
            .heading(level: 1, text: "August Board Meeting"),
            .blank,
            .paragraph(indent: 0, text: "**Present:** Maria Lopez (Chair)"),
            .heading(level: 2, text: "Treasurer's report"),
            .heading(level: 2, text: "Old Business"),
            .heading(level: 2, text: "CALL TO ORDER"),
            .heading(level: 2, text: "Action Items"),
            .item(level: 0, marker: "•", text: "Dev: circulate the budget."),
            .item(level: 1, marker: "•", text: "nested point"),
            .item(level: 0, marker: "2.", text: "Second motion"),
            .item(level: 0, marker: "12.", text: "Twelfth"),
            .paragraph(indent: 1, text: "Moved by: [name]"),
            .rule,
            .paragraph(indent: 0, text: "Respectfully submitted,"),
        ])
    }

    func testTheOutlineFallbackExports() throws {
        let input = MinutesInput(kind: .board, title: "Planning", date: date, duration: 600,
                                 attendees: [(name: "Maria Lopez", role: "Chair")],
                                 lines: [.init(time: 5, speaker: "Maria Lopez", text: "I'll book the hall.")],
                                 motionMarks: [5])
        let text = try pages(pdf(body: MinutesWriter.outline(input))).joined()
        XCTAssertTrue(text.contains("MINUTES — PLANNING"))
        XCTAssertTrue(text.contains("Maria Lopez: I'll book the hall."))
        XCTAssertTrue(text.contains("ADJOURNMENT"))
    }

    func testFileIsNamedAfterTheMeeting() throws {
        XCTAssertEqual(pdf(body: "").fileName, "October Board Meeting.pdf")
        XCTAssertEqual(pdf(title: "Q3 / Q4: Budget?", body: "").fileName, "Q3 - Q4- Budget.pdf")
        XCTAssertEqual(pdf(.adHoc, title: "  ", body: "").fileName, "Summary.pdf")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try pdf(body: "Hello.").write(to: folder)
        XCTAssertEqual(url.lastPathComponent, "October Board Meeting.pdf")
        XCTAssertNotNil(PDFDocument(url: url))
    }
}
