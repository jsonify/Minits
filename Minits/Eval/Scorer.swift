import Foundation

/// What a line should have been attributed to, according to the labels.
enum LineTruth: Equatable, Sendable {
    /// `overlapping` is true when a second member also covers a real share of the line.
    case member(String, overlapping: Bool)
    case nonMember
}

enum Scorer {
    /// A second speaker covering more than this share of a line makes it an overlap line.
    static let overlapShare = 0.30

    /// Ground truth for one line, or nil when the line has no length to judge.
    static func truth(for line: LineUnderTest, in truth: GroundTruth) -> LineTruth? {
        let duration = line.span.duration
        guard duration > 0 else { return nil }

        var covered: [String: Double] = [:]
        for interval in truth.intervals {
            covered[interval.speaker, default: 0] += min(duration, line.span.overlap(with: interval.span))
        }
        let nonMember = truth.nonMemberSpans.reduce(0) { $0 + line.span.overlap(with: $1) }

        // Largest share wins; alphabetical order settles ties so results are repeatable.
        let ranked = covered.filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        guard let best = ranked.first, best.value >= nonMember else { return .nonMember }

        let overlapping = ranked.dropFirst().contains { $0.value / duration > overlapShare }
            && best.value / duration > overlapShare
        return .member(best.key, overlapping: overlapping)
    }

    /// Judges every line that has a length. Guests are right on non-member speech and wrong on a member's.
    static func score(lines: [LineUnderTest], truth: GroundTruth) -> [ScoredLine] {
        lines.compactMap { line in
            guard let expected = Self.truth(for: line, in: truth) else { return nil }
            let correct: Bool
            switch expected {
            case .member(let name, _): correct = line.speaker == name
            case .nonMember: correct = line.speaker == nil
            }
            return ScoredLine(line: line, truth: expected, correct: correct)
        }
    }
}

struct ScoredLine: Equatable, Sendable {
    var line: LineUnderTest
    var truth: LineTruth
    var correct: Bool

    /// Wrong and not flagged for review: the error a user would never notice.
    var isUnflaggedError: Bool { !correct && !line.needsReview }
}

/// Headline numbers for a set of scored lines. Rates are 0 when there is nothing to divide.
struct Metrics: Equatable, Sendable {
    /// Seconds a reviewer needs to decide on each flagged line, on top of listening to it.
    static let decisionSeconds = 4.0

    var lineCount = 0
    var correctCount = 0
    var flaggedCount = 0
    var wrongCount = 0
    var wrongFlaggedCount = 0
    var unflaggedErrorCount = 0

    var totalSeconds = 0.0
    var unflaggedErrorSeconds = 0.0
    var correctSeconds = 0.0
    var flaggedSeconds = 0.0

    /// Length of the whole meeting, used to scale review time to an hour.
    var meetingSeconds = 0.0

    init(lines: [ScoredLine], meetingSeconds: Double) {
        self.meetingSeconds = meetingSeconds
        for scored in lines {
            let seconds = scored.line.span.duration
            lineCount += 1
            totalSeconds += seconds
            if scored.correct {
                correctCount += 1
                correctSeconds += seconds
            } else {
                wrongCount += 1
                if scored.line.needsReview { wrongFlaggedCount += 1 }
            }
            if scored.line.needsReview {
                flaggedCount += 1
                flaggedSeconds += seconds
            }
            if scored.isUnflaggedError {
                unflaggedErrorCount += 1
                unflaggedErrorSeconds += seconds
            }
        }
    }

    var accuracy: Double { ratio(correctCount, lineCount) }
    var accuracyByDuration: Double { ratio(correctSeconds, totalSeconds) }
    /// The primary metric: target under 1%.
    var unflaggedErrorRate: Double { ratio(unflaggedErrorCount, lineCount) }
    var unflaggedErrorRateByDuration: Double { ratio(unflaggedErrorSeconds, totalSeconds) }
    var flaggedRate: Double { ratio(flaggedCount, lineCount) }

    /// Share of wrong lines that were flagged; nil when nothing was wrong.
    var flagRecall: Double? { wrongCount == 0 ? nil : Double(wrongFlaggedCount) / Double(wrongCount) }

    /// Estimated review time per hour of meeting: play each flagged line once, plus time to decide.
    var reviewMinutesPerHour: Double {
        guard meetingSeconds > 0 else { return 0 }
        let reviewSeconds = flaggedSeconds + Self.decisionSeconds * Double(flaggedCount)
        return reviewSeconds / meetingSeconds * 3600 / 60
    }

    private func ratio(_ top: Int, _ bottom: Int) -> Double { bottom == 0 ? 0 : Double(top) / Double(bottom) }
    private func ratio(_ top: Double, _ bottom: Double) -> Double { bottom == 0 ? 0 : top / bottom }
}
