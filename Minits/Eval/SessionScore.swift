import Foundation

/// How the lines in one confidence range fared; shows whether `confidence` can be trusted.
struct ConfidenceBucket: Equatable, Sendable {
    var lower: Double
    var upper: Double
    var lineCount = 0
    var wrongCount = 0
    var unflaggedErrorCount = 0
}

/// Scored lines for one session (or several pooled together) plus the breakdowns the report shows.
struct SessionScore: Equatable, Sendable {
    /// Row and column label for lines the engine called a guest, or truth that was non-member speech.
    static let guestLabel = "(guest)"
    static let nonMemberLabel = "(non-member)"
    static let shortLineSeconds = 1.0
    static let bucketCount = 4

    var lines: [ScoredLine]
    var meetingSeconds: Double

    var metrics: Metrics { Metrics(lines: lines, meetingSeconds: meetingSeconds) }

    var overlapMetrics: Metrics {
        Metrics(lines: lines.filter { line in
            if case .member(_, true) = line.truth { return true }
            return false
        }, meetingSeconds: meetingSeconds)
    }

    var shortLineMetrics: Metrics {
        Metrics(lines: lines.filter { $0.line.span.duration < Self.shortLineSeconds }, meetingSeconds: meetingSeconds)
    }

    /// Line counts by true speaker, then by who the engine said it was.
    var confusion: [String: [String: Int]] {
        var matrix: [String: [String: Int]] = [:]
        for scored in lines {
            let actual: String
            switch scored.truth {
            case .member(let name, _): actual = name
            case .nonMember: actual = Self.nonMemberLabel
            }
            matrix[actual, default: [:]][scored.line.speaker ?? Self.guestLabel, default: 0] += 1
        }
        return matrix
    }

    var confidenceBuckets: [ConfidenceBucket] {
        let width = 1.0 / Double(Self.bucketCount)
        var buckets = (0..<Self.bucketCount).map {
            ConfidenceBucket(lower: Double($0) * width, upper: Double($0 + 1) * width)
        }
        for scored in lines {
            let index = min(Self.bucketCount - 1, max(0, Int(scored.line.confidence / width)))
            buckets[index].lineCount += 1
            if !scored.correct { buckets[index].wrongCount += 1 }
            if scored.isUnflaggedError { buckets[index].unflaggedErrorCount += 1 }
        }
        return buckets
    }
}

extension Scorer {
    /// Combines sessions into one score; rates are then pooled by line count and, separately, by duration.
    static func pool(_ sessions: [SessionScore]) -> SessionScore {
        SessionScore(
            lines: sessions.flatMap(\.lines),
            meetingSeconds: sessions.reduce(0) { $0 + $1.meetingSeconds })
    }
}
