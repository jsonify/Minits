import Foundation

/// Picks labeled intervals to verify by ear, so a bad label run is caught before it skews every score.
/// The pick is spread evenly over the session (not random) so reruns give the same clips.
enum SpotCheck {
    /// Shorter intervals are too brief to tell voices apart by ear.
    static let minSeconds = 1.0
    /// Clips include a little audio either side of the label, and stop after `maxClipSeconds`.
    static let paddingSeconds = 0.3
    static let maxClipSeconds = 10.0
    /// Issue #5's bar: at least 19 of 20 labels right.
    static let defaultCount = 20

    struct Clip: Equatable, Sendable {
        var number: Int
        var interval: LabeledInterval
        /// The audio to cut from table.wav.
        var span: TimeSpan
        /// Other members labeled as talking during this interval.
        var overlapping: [String]

        var fileName: String {
            let start = Int(interval.start)
            return String(format: "%02d-%@-%02d%02d.wav", number, interval.speaker, start / 60, start % 60)
        }
    }

    static func clips(from truth: GroundTruth, count: Int = defaultCount) -> [Clip] {
        let eligible = truth.intervals
            .filter { $0.end - $0.start >= minSeconds }
            .sorted { ($0.start, $0.speaker) < ($1.start, $1.speaker) }
        let take = min(max(0, count), eligible.count)
        guard take > 0 else { return [] }
        return (0..<take).map { i in
            // Middle of each of `take` equal slices of the list.
            let interval = eligible[Int((Double(i) + 0.5) * Double(eligible.count) / Double(take))]
            let start = max(0, interval.start - paddingSeconds)
            let end = min(interval.end + paddingSeconds, start + maxClipSeconds)
            let overlapping = Set(truth.intervals
                .filter { $0.speaker != interval.speaker && $0.span.overlap(with: interval.span) > 0 }
                .map(\.speaker)).sorted()
            return Clip(number: i + 1, interval: interval, span: TimeSpan(start: start, end: end),
                        overlapping: overlapping)
        }
    }

    /// Fewest correct labels that still meets the bar (19 of 20).
    static func passMark(for count: Int) -> Int { count - count / 20 }

    /// A checklist to fill in while listening to the clips.
    static func checklist(session: String, clips: [Clip]) -> String {
        var text = """
        # Spot check: \(session)

        Play each clip (cut from table.wav) and mark ✅ when the labeled member is talking, ❌ when someone else is.
        When the Overlap column names someone, the clip is crosstalk: ✅ if the labeled member is one of the voices.
        Target: at least \(passMark(for: clips.count)) of \(clips.count) correct. Fewer means the labels need fixing before any score is trusted.

        | # | Clip | Time | Labeled | Overlap | Correct? | Notes |
        |---|---|---|---|---|---|---|

        """
        for clip in clips {
            let time = "\(SessionCheck.clock(clip.interval.start))–\(SessionCheck.clock(clip.interval.end))"
            let overlap = clip.overlapping.joined(separator: ", ")
            text += "| \(clip.number) | \(clip.fileName) | \(time) | \(clip.interval.speaker) | \(overlap) |  |  |\n"
        }
        text += "\nCorrect: __ / \(clips.count)\n"
        return text
    }
}
