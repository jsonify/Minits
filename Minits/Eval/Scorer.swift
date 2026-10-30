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
}
