import Foundation

/// Cuts one transcript line in two where a second voice starts, for a line Minits put under one speaker when two
/// people spoke ("anything there? | Oh, yeah, um,").
///
/// Lines made since Minits kept word timings know when each word starts, so the cut falls exactly where the second
/// person's first word begins. Older lines don't, so the time is estimated from how far through the text the cut is.
enum LineSplit {
    /// The line's words, as the split sheet shows them.
    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    struct Halves: Equatable {
        let firstText: String
        let secondText: String
        /// Where the second half starts (and the first now ends), in seconds.
        let time: Double
        let firstWordStarts: [Double]
        let secondWordStarts: [Double]
        /// The time came from the words' own timings rather than an estimate.
        let isExact: Bool
    }

    /// Splits `text` before word `index`, which must leave at least one word on each side; nil otherwise.
    static func halves(text: String, start: Double, end: Double, wordStarts: [Double], at index: Int) -> Halves? {
        let words = words(text)
        guard index > 0, index < words.count else { return nil }
        let exact = wordStarts.count == words.count
        var time: Double
        if exact {
            time = wordStarts[index]
        } else {
            let before = words[..<index].reduce(0) { $0 + $1.count }
            let total = max(words.reduce(0) { $0 + $1.count }, 1)
            time = start + (end - start) * Double(before) / Double(total)
        }
        // Keep the cut inside the line so both halves have some audio and the second sorts after the first.
        let lowest = start + 0.01
        let highest = max(lowest, end - 0.01)
        time = min(max(time, lowest), highest)
        return Halves(
            firstText: words[..<index].joined(separator: " "),
            secondText: words[index...].joined(separator: " "),
            time: time,
            firstWordStarts: exact ? Array(wordStarts[..<index]) : [],
            secondWordStarts: exact ? Array(wordStarts[index...]) : [],
            isExact: exact)
    }

    /// What a split line's card says until you pick who said it.
    static let reviewNote = "Split: who said this part?"
}

extension Meeting {
    /// Splits `line` before word `index` into two lines, both flagged for Review with the line's guesses, and
    /// returns the new second half (nil if `index` doesn't leave a word on each side). Save the context afterwards.
    @discardableResult
    func split(_ line: TranscriptLine, atWord index: Int) -> TranscriptLine? {
        guard let halves = LineSplit.halves(text: line.text, start: line.start, end: line.end,
                                            wordStarts: line.wordStarts, at: index) else { return nil }
        let second = TranscriptLine(start: halves.time, end: line.end, text: halves.secondText)
        second.wordStarts = halves.secondWordStarts
        second.speakerID = line.speakerID
        second.speakerName = line.speakerName
        second.alternateSpeakerID = line.alternateSpeakerID
        second.confidence = line.confidence

        line.end = halves.time
        line.text = halves.firstText
        line.wordStarts = halves.firstWordStarts

        for half in [line, second] {
            half.needsReview = true
            half.reviewNote = LineSplit.reviewNote
        }
        lines.append(second)
        status = .needsReview
        return second
    }
}
