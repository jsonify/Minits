import CoreGraphics
import CoreText
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The minutes or summary as a plain, printable PDF: black on white, not the SK-1 look. It has the meeting's title and
/// date, the attendance for a board meeting (who was here and who wasn't, with roles), the body as edited with its
/// Markdown headings and lists kept, and page numbers.
///
/// Drawn on the device with Core Text and Core Graphics, which work the same on iOS and macOS. Pages break between
/// lines (a Core Text frame only holds whole lines), and a heading is never left alone at the bottom of a page.
struct MinutesPDF: Sendable {
    struct Person: Equatable, Sendable {
        let name: String
        let role: String

        /// "Maria Lopez (Chair)", or just the name.
        var label: String { role.isEmpty ? name : "\(name) (\(role))" }
    }

    var kind: MeetingKind
    var title: String
    var date: Date
    /// Members who were here, in roll-call order.
    var present: [Person]
    /// Members who weren't. Only shown for a board meeting.
    var absent: [Person]
    /// The minutes or summary as edited (Markdown or plain text).
    var body: String

    init(kind: MeetingKind, title: String, date: Date, present: [Person], absent: [Person], body: String) {
        self.kind = kind
        self.title = title
        self.date = date
        self.present = present
        self.absent = absent
        self.body = body
    }

    /// `members` in roll-call order.
    init(meeting: Meeting, members: [Member]) {
        let here = Set(meeting.attendeeIDs)
        self.init(kind: meeting.kind,
                  title: meeting.title,
                  date: meeting.startedAt,
                  present: members.filter { here.contains($0.id) }.map { Person(name: $0.name, role: $0.role) },
                  absent: members.filter { !here.contains($0.id) }.map { Person(name: $0.name, role: $0.role) },
                  body: meeting.minutes ?? "")
    }

    // MARK: File name

    /// The meeting's title made safe for a file name ("October Board Meeting"), or "Minutes" / "Summary" without one.
    var baseName: String {
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        let cleaned = title.unicodeScalars.map { unsafe.contains($0) ? "-" : String($0) }.joined()
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". -"))
        return cleaned.isEmpty ? kind.documentName : String(cleaned.prefix(120))
    }

    /// "October Board Meeting.pdf"
    var fileName: String { baseName + ".pdf" }

    /// Writes the PDF into a new folder inside `folder`, so the file keeps the meeting's name. Returns its URL.
    func write(to folder: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let directory = folder.appendingPathComponent("Minits-PDF-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        try data().write(to: url, options: .atomic)
        return url
    }

    // MARK: Page

    /// US Letter where the region uses US measurements, otherwise A4, in points.
    static var defaultPageSize: CGSize {
        Locale.current.measurementSystem == .us ? CGSize(width: 612, height: 792) : CGSize(width: 595, height: 842)
    }

    static let margin: CGFloat = 54
    /// Room under the text for the page number.
    static let footerHeight: CGFloat = 28

    /// Where the text goes on a page (Core Graphics coordinates, origin bottom left).
    static func textRect(for pageSize: CGSize) -> CGRect {
        CGRect(x: margin, y: margin + footerHeight,
               width: pageSize.width - 2 * margin, height: pageSize.height - 2 * margin - footerHeight)
    }

    /// The PDF file's bytes.
    func data(pageSize: CGSize = MinutesPDF.defaultPageSize) -> Data {
        let frames = Self.paginate(attributedText(), in: Self.textRect(for: pageSize))
        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let info: [String: Any] = [kCGPDFContextTitle as String: title.isEmpty ? kind.documentName : title,
                                   kCGPDFContextCreator as String: "Minits"]
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary)
        else { return Data() }

        let pageCount = max(frames.count, 1)
        for page in 0..<pageCount {
            context.beginPDFPage(nil)
            context.textMatrix = .identity
            if page < frames.count { CTFrameDraw(frames[page], context) }
            Self.drawPageNumber(page + 1, of: pageCount, in: context, pageSize: pageSize)
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    private static func drawPageNumber(_ page: Int, of count: Int, in context: CGContext, pageSize: CGSize) {
        let text = NSAttributedString(string: "Page \(page) of \(count)",
                                      attributes: Style.attributes(font: Style.font(.regular, 9)))
        let line = CTLineCreateWithAttributedString(text as CFAttributedString)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        context.textPosition = CGPoint(x: (pageSize.width - width) / 2, y: margin)
        CTLineDraw(line, context)
    }

    /// Splits the text into one Core Text frame per page. A frame only holds whole lines, so no line is cut between
    /// pages. When a page would end on a heading, the heading moves to the next page with the text it introduces.
    static func paginate(_ text: NSAttributedString, in rect: CGRect) -> [CTFrame] {
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        let path = CGPath(rect: rect, transform: nil)
        var frames: [CTFrame] = []
        var location = 0
        while location < text.length {
            var frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            var visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { break }
            if visible.location + visible.length < text.length,
               let cut = trailingHeadingStart(in: frame, text: text), cut > location {
                frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: cut - location),
                                                 path, nil)
                visible = CTFrameGetVisibleStringRange(frame)
            }
            frames.append(frame)
            location = visible.location + visible.length
        }
        return frames
    }

    /// Where the heading starts that ends this frame, if it ends with one and has something before it.
    private static func trailingHeadingStart(in frame: CTFrame, text: NSAttributedString) -> Int? {
        let lines = (CTFrameGetLines(frame) as? [CTLine]) ?? []
        var first: Int?
        for index in lines.indices.reversed() {
            let start = CTLineGetStringRange(lines[index]).location
            guard start < text.length, text.attribute(Style.keepWithNext, at: start, effectiveRange: nil) != nil
            else { break }
            first = index
        }
        guard let first, first > 0 else { return nil }
        return CTLineGetStringRange(lines[first]).location
    }

    // MARK: Text

    /// Everything on the pages, before it's split into pages.
    func attributedText() -> NSAttributedString {
        let text = NSMutableAttributedString()
        let heading = title.isEmpty ? kind.documentName : title
        text.append(Style.paragraph(heading, font: Style.font(.bold, 20), after: 4))
        let when = date.formatted(date: .complete, time: .shortened)
        text.append(Style.paragraph("\(kind.label) · \(when)", font: Style.font(.regular, 11), after: 10))

        if kind == .board {
            text.append(Style.heading("Attendance", level: 2))
            text.append(Style.labelled("Present", present.isEmpty ? "Not recorded" : present.map(\.label).joined(separator: ", ")))
            text.append(Style.labelled("Absent", absent.isEmpty ? "None" : absent.map(\.label).joined(separator: ", ")))
        }

        var gap = true
        for block in Self.blocks(from: body) {
            switch block {
            case .blank:
                gap = true
                continue
            case .rule:
                text.append(Style.paragraph(" ", font: Style.font(.regular, 6), before: 4, after: 4))
            case .heading(let level, let words):
                text.append(Style.heading(words, level: level))
            case .paragraph(let indent, let words):
                text.append(Style.body(words, indent: CGFloat(indent) * 18, before: gap ? 8 : 2))
            case .item(let level, let marker, let words):
                text.append(Style.item(marker, words, level: level, before: gap ? 6 : 2))
            }
            gap = false
        }
        // Drop the final newline so it doesn't make an empty last page.
        if text.string.hasSuffix("\n") { text.deleteCharacters(in: NSRange(location: text.length - 1, length: 1)) }
        return text
    }

    // MARK: Markdown

    /// One line of the body, as it's laid out.
    enum Block: Equatable {
        /// `#` is level 1; bold-only lines, ALL-CAPS lines and the drafts' section names are level 2.
        case heading(level: Int, text: String)
        /// A line of text, indented by `indent` steps when the draft indents it.
        case paragraph(indent: Int, text: String)
        /// A bullet ("•") or numbered ("1.") item, nested by `level`.
        case item(level: Int, marker: String, text: String)
        case rule
        case blank
    }

    /// The section names the drafts use as plain-text headings (see `MinutesWriter.Prompts`).
    static let sectionNames: Set<String> = [
        "call to order", "attendance", "approval of prior minutes", "reports", "old business", "new business",
        "motions", "action items", "adjournment", "summary", "topics discussed", "decisions", "open questions",
    ]

    /// The body's lines as headings, items and paragraphs. Inline Markdown (bold, italics, code) is left in the text
    /// and drawn later.
    static func blocks(from markdown: String) -> [Block] {
        var blocks: [Block] = []
        for raw in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let leading = line.prefix { $0 == " " }.count

            if trimmed.isEmpty {
                if blocks.last != .blank { blocks.append(.blank) }
                continue
            }
            if let hashes = trimmed.firstIndex(where: { $0 != "#" }), trimmed.first == "#",
               trimmed.distance(from: trimmed.startIndex, to: hashes) <= 6, trimmed[hashes] == " " {
                let level = trimmed.distance(from: trimmed.startIndex, to: hashes)
                let words = trimmed[hashes...].trimmingCharacters(in: CharacterSet(charactersIn: " #"))
                blocks.append(.heading(level: level, text: words))
                continue
            }
            if trimmed.count >= 3, Set(trimmed).count == 1, "-*_".contains(trimmed.first!) {
                blocks.append(.rule)
                continue
            }
            if let bold = boldOnly(trimmed) {
                blocks.append(.heading(level: 2, text: bold))
                continue
            }
            if let bullet = ["- ", "* ", "+ ", "• "].first(where: { trimmed.hasPrefix($0) }) {
                blocks.append(.item(level: min(leading / 2, 3), marker: "•",
                                    text: String(trimmed.dropFirst(bullet.count)).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if let item = numbered(trimmed) {
                blocks.append(.item(level: min(leading / 2, 3), marker: item.number, text: item.text))
                continue
            }
            if isHeadingLine(trimmed) {
                blocks.append(.heading(level: 2, text: trimmed.hasSuffix(":") ? String(trimmed.dropLast()) : trimmed))
                continue
            }
            blocks.append(.paragraph(indent: min(leading / 2, 3), text: trimmed))
        }
        while blocks.first == .blank { blocks.removeFirst() }
        while blocks.last == .blank { blocks.removeLast() }
        return blocks
    }

    /// "1. Text" or "1) Text" → ("1.", "Text").
    private static func numbered(_ line: String) -> (number: String, text: String)? {
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard (1...3).contains(digits.count) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let mark = rest.first, mark == "." || mark == ")", rest.dropFirst().first == " " else { return nil }
        return ("\(digits).", rest.dropFirst(2).trimmingCharacters(in: .whitespaces))
    }

    /// "**Treasurer's report**" or "**Motions:**" → the words inside.
    private static func boldOnly(_ line: String) -> String? {
        guard line.count > 4, line.hasPrefix("**") else { return nil }
        var inner = line.dropFirst(2)
        if inner.hasSuffix("**:") { inner = inner.dropLast(3) } else if inner.hasSuffix("**") { inner = inner.dropLast(2) } else { return nil }
        guard !inner.isEmpty, !inner.contains("**") else { return nil }
        let words = inner.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        return words.isEmpty ? nil : words
    }

    /// An ALL-CAPS line ("CALL TO ORDER", "MINUTES — OCTOBER BOARD MEETING") or one of the drafts' section names on its
    /// own line ("Action Items", "Decisions:").
    private static func isHeadingLine(_ line: String) -> Bool {
        let name = line.hasSuffix(":") ? String(line.dropLast()) : line
        if sectionNames.contains(name.lowercased()) { return true }
        let letters = line.filter(\.isLetter)
        return letters.count >= 3 && line.count <= 80 && !line.hasPrefix("[")
            && !letters.contains(where: \.isLowercase) && letters.contains(where: \.isUppercase)
    }

    // MARK: Style

    /// Fonts and paragraph styles: Helvetica, black, on both iOS and macOS.
    enum Style {
        enum Weight { case regular, bold, italic, boldItalic, code }

        /// Marks heading text, so a page doesn't end on it.
        static let keepWithNext = NSAttributedString.Key("MinitsKeepWithNext")

        static func font(_ weight: Weight, _ size: CGFloat) -> CTFont {
            let name: String
            switch weight {
            case .regular: name = "Helvetica"
            case .bold: name = "Helvetica-Bold"
            case .italic: name = "Helvetica-Oblique"
            case .boldItalic: name = "Helvetica-BoldOblique"
            case .code: name = "Courier"
            }
            return CTFontCreateWithName(name as CFString, size, nil)
        }

        static let black = CGColor(gray: 0, alpha: 1)

        static func attributes(font: CTFont, style: CTParagraphStyle? = nil) -> [NSAttributedString.Key: Any] {
            var attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): black,
            ]
            if let style { attributes[NSAttributedString.Key(kCTParagraphStyleAttributeName as String)] = style }
            return attributes
        }

        static func paragraphStyle(headIndent: CGFloat = 0, firstLineIndent: CGFloat = 0, before: CGFloat = 0,
                                   after: CGFloat = 0, lineHeight: CGFloat = 1.15) -> CTParagraphStyle {
            let values: [CGFloat] = [headIndent, firstLineIndent, before, after, lineHeight]
            let tabs = [CTTextTabCreate(.left, Double(headIndent), nil)] as CFArray
            return values.withUnsafeBufferPointer { value in
                withUnsafePointer(to: tabs) { tabStops in
                    let size = MemoryLayout<CGFloat>.size
                    let settings = [
                        CTParagraphStyleSetting(spec: .headIndent, valueSize: size, value: value.baseAddress! + 0),
                        CTParagraphStyleSetting(spec: .firstLineHeadIndent, valueSize: size, value: value.baseAddress! + 1),
                        CTParagraphStyleSetting(spec: .paragraphSpacingBefore, valueSize: size, value: value.baseAddress! + 2),
                        CTParagraphStyleSetting(spec: .paragraphSpacing, valueSize: size, value: value.baseAddress! + 3),
                        CTParagraphStyleSetting(spec: .lineHeightMultiple, valueSize: size, value: value.baseAddress! + 4),
                        CTParagraphStyleSetting(spec: .tabStops, valueSize: MemoryLayout<CFArray>.size, value: tabStops),
                    ]
                    return CTParagraphStyleCreate(settings, settings.count)
                }
            }
        }

        /// One plain paragraph, ending in a newline.
        static func paragraph(_ text: String, font: CTFont, before: CGFloat = 0, after: CGFloat = 0) -> NSAttributedString {
            NSAttributedString(string: text + "\n",
                               attributes: attributes(font: font, style: paragraphStyle(before: before, after: after)))
        }

        static func heading(_ text: String, level: Int) -> NSAttributedString {
            let size: CGFloat = level <= 1 ? 16 : level == 2 ? 13.5 : 12
            let result = NSMutableAttributedString(attributedString: inline(
                text, size: size, bold: true, style: paragraphStyle(before: level <= 1 ? 16 : 12, after: 4)))
            result.addAttribute(keepWithNext, value: true, range: NSRange(location: 0, length: result.length))
            return result
        }

        /// "Present: Maria Lopez (Chair), …" with the label in bold.
        static func labelled(_ label: String, _ value: String) -> NSAttributedString {
            let style = paragraphStyle(before: 2, after: 2)
            let result = NSMutableAttributedString(string: label + ": ", attributes: attributes(font: font(.bold, 11), style: style))
            result.append(NSAttributedString(string: value + "\n", attributes: attributes(font: font(.regular, 11), style: style)))
            return result
        }

        static func body(_ text: String, indent: CGFloat, before: CGFloat) -> NSAttributedString {
            inline(text, size: 11, style: paragraphStyle(headIndent: indent, firstLineIndent: indent, before: before))
        }

        /// A bullet or numbered item with a hanging indent, so wrapped lines line up with the text, not the marker.
        static func item(_ marker: String, _ text: String, level: Int, before: CGFloat) -> NSAttributedString {
            let indent = CGFloat(level) * 18 + (marker == "•" ? 14 : 22)
            let style = paragraphStyle(headIndent: indent, firstLineIndent: CGFloat(level) * 18, before: before)
            let result = NSMutableAttributedString(string: marker + "\t", attributes: attributes(font: font(.regular, 11), style: style))
            result.append(inline(text, size: 11, style: style))
            return result
        }

        /// Text with its inline Markdown (bold, italics, code) drawn and the asterisks removed, ending in a newline.
        static func inline(_ text: String, size: CGFloat, bold: Bool = false, style: CTParagraphStyle) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            if let parsed = try? AttributedString(markdown: text, options: options) {
                for run in parsed.runs {
                    let intent = run.inlinePresentationIntent ?? []
                    let strong = bold || intent.contains(.stronglyEmphasized)
                    let italic = intent.contains(.emphasized)
                    let weight: Weight = intent.contains(.code) ? .code
                        : strong && italic ? .boldItalic : strong ? .bold : italic ? .italic : .regular
                    result.append(NSAttributedString(string: String(parsed[run.range].characters),
                                                     attributes: attributes(font: font(weight, size), style: style)))
                }
            } else {
                result.append(NSAttributedString(string: text,
                                                 attributes: attributes(font: font(bold ? .bold : .regular, size), style: style)))
            }
            result.append(NSAttributedString(string: "\n", attributes: attributes(font: font(.regular, size), style: style)))
            return result
        }
    }
}

// MARK: Sharing

extension MinutesPDF: Transferable {
    /// The share sheet (iPhone) and save panel (Mac) get a PDF file named after the meeting, made when it's needed.
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { pdf in
            SentTransferredFile(try pdf.write())
        }
    }
}
