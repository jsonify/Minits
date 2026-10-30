import Foundation

// Plain types for the speaker-attribution evaluation. No FluidAudio here, so the scorer can be
// unit tested without models; the eval CLI maps VoiceEngine's output into these.

struct TimeSpan: Codable, Equatable, Sendable {
    var start: Double
    var end: Double

    var duration: Double { max(0, end - start) }

    func overlap(with other: TimeSpan) -> Double {
        max(0, min(end, other.end) - max(start, other.start))
    }
}

/// One stretch where a member was actually talking. Intervals from different members may overlap.
struct LabeledInterval: Codable, Equatable, Sendable {
    var speaker: String
    var start: Double
    var end: Double

    var span: TimeSpan { TimeSpan(start: start, end: end) }
}

/// The contents of a session's labels.json.
struct GroundTruth: Codable, Equatable, Sendable {
    var intervals: [LabeledInterval]
    /// Stretches of clearly non-member speech; a Guest attribution is correct here.
    var nonMemberSpans: [TimeSpan] = []

    init(intervals: [LabeledInterval], nonMemberSpans: [TimeSpan] = []) {
        self.intervals = intervals
        self.nonMemberSpans = nonMemberSpans
    }

    /// labels.json is hand-editable, so `nonMemberSpans` may be left out.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        intervals = try container.decode([LabeledInterval].self, forKey: .intervals)
        nonMemberSpans = try container.decodeIfPresent([TimeSpan].self, forKey: .nonMemberSpans) ?? []
    }
}

/// One line of transcript as the engine produced it, reduced to what scoring needs.
struct LineUnderTest: Equatable, Sendable {
    var start: Double
    var end: Double
    var text: String
    /// Member name the engine chose, or nil when it called the voice a guest.
    var speaker: String?
    var needsReview: Bool
    var confidence: Double

    var span: TimeSpan { TimeSpan(start: start, end: end) }
}
