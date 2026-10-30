import Foundation

/// The thresholds a run used. Mirrors `VoiceTuning` so this file stays free of FluidAudio.
struct TuningReport: Codable, Equatable, Sendable {
    var acceptSimilarity: Double
    var sureSimilarity: Double
    var minimumMargin: Double
    var overrideGap: Double

    var summary: String {
        "accept \(acceptSimilarity), sure \(sureSimilarity), margin \(minimumMargin), override gap \(overrideGap)"
    }
}

struct MetricsReport: Codable, Equatable, Sendable {
    var lines: Int
    var correct: Int
    var wrong: Int
    var flagged: Int
    var unflaggedErrors: Int
    var accuracy: Double
    var accuracyByDuration: Double
    var unflaggedErrorRate: Double
    var unflaggedErrorRateByDuration: Double
    var flaggedRate: Double
    var flagRecall: Double?
    var reviewMinutesPerHour: Double

    init(_ m: Metrics) {
        lines = m.lineCount
        correct = m.correctCount
        wrong = m.wrongCount
        flagged = m.flaggedCount
        unflaggedErrors = m.unflaggedErrorCount
        accuracy = m.accuracy
        accuracyByDuration = m.accuracyByDuration
        unflaggedErrorRate = m.unflaggedErrorRate
        unflaggedErrorRateByDuration = m.unflaggedErrorRateByDuration
        flaggedRate = m.flaggedRate
        flagRecall = m.flagRecall
        reviewMinutesPerHour = m.reviewMinutesPerHour
    }
}

struct BucketReport: Codable, Equatable, Sendable {
    var lower: Double
    var upper: Double
    var lines: Int
    var wrong: Int
    var unflaggedErrors: Int
}

struct SessionReport: Codable, Equatable, Sendable {
    var name: String
    var meetingSeconds: Double
    var metrics: MetricsReport
    var overlap: MetricsReport
    var shortLines: MetricsReport
    var confusion: [String: [String: Int]]
    var confidenceBuckets: [BucketReport]

    init(name: String, score: SessionScore) {
        self.name = name
        meetingSeconds = score.meetingSeconds
        metrics = MetricsReport(score.metrics)
        overlap = MetricsReport(score.overlapMetrics)
        shortLines = MetricsReport(score.shortLineMetrics)
        confusion = score.confusion
        confidenceBuckets = score.confidenceBuckets.map {
            BucketReport(lower: $0.lower, upper: $0.upper, lines: $0.lineCount,
                         wrong: $0.wrongCount, unflaggedErrors: $0.unflaggedErrorCount)
        }
    }
}

/// A line that was wrong and not flagged, with enough to find it and listen to it.
struct UnflaggedErrorLine: Codable, Equatable, Sendable {
    var session: String
    var start: Double
    var text: String
    var truth: String
    var got: String
    var score: Double

    enum CodingKeys: String, CodingKey {
        case session, start, text, truth = "true", got, score
    }
}

/// Everything one `minits-eval run` measured. Encodes to the same bytes for the same inputs.
struct EvalReport: Codable, Equatable, Sendable {
    var fluidAudioVersion: String
    var tuning: TuningReport
    var sessions: [SessionReport]
    var overall: SessionReport
    var unflaggedErrors: [UnflaggedErrorLine]

    init(tuning: TuningReport, fluidAudioVersion: String, sessions: [(name: String, score: SessionScore)]) {
        self.tuning = tuning
        self.fluidAudioVersion = fluidAudioVersion
        self.sessions = sessions.map { SessionReport(name: $0.name, score: $0.score) }
        overall = SessionReport(name: "overall", score: Scorer.pool(sessions.map(\.score)))
        unflaggedErrors = sessions.flatMap { session in
            session.score.lines.filter(\.isUnflaggedError).map { scored in
                let truth: String
                switch scored.truth {
                case .member(let name, _): truth = name
                case .nonMember: truth = SessionScore.nonMemberLabel
                }
                return UnflaggedErrorLine(
                    session: session.name, start: scored.line.start, text: scored.line.text,
                    truth: truth, got: scored.line.speaker ?? SessionScore.guestLabel,
                    score: scored.line.confidence)
            }
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> EvalReport {
        try JSONDecoder().decode(EvalReport.self, from: data)
    }

    /// The human-readable report: one row per session plus overall, then every unflagged error.
    func table() -> String {
        var out = "Tuning: \(tuning.summary)  (FluidAudio \(fluidAudioVersion))\n\n"
        let header = ["session", "lines", "accuracy", "unflagged err", "flagged", "flag recall", "review min/h"]
        var rows = sessions.map(Self.row) + [Self.row(overall)]
        rows.insert(header, at: 0)
        let widths = header.indices.map { column in rows.map { $0[column].count }.max() ?? 0 }
        for row in rows {
            out += zip(row, widths).enumerated().map { column, cell in
                column == 0 ? cell.0.padding(toLength: cell.1, withPad: " ", startingAt: 0)
                    : String(repeating: " ", count: cell.1 - cell.0.count) + cell.0
            }.joined(separator: "  ") + "\n"
        }

        out += "\nWrong and unflagged (\(unflaggedErrors.count)):\n"
        for line in unflaggedErrors {
            out += "  \(line.session)  \(Self.clock(line.start))  true \(line.truth), got \(line.got), "
                + "score \(Self.decimal(line.score))  \"\(line.text)\"\n"
        }
        return out
    }

    private static func row(_ session: SessionReport) -> [String] {
        let m = session.metrics
        return [session.name, "\(m.lines)", percent(m.accuracy), percent(m.unflaggedErrorRate),
                percent(m.flaggedRate), m.flagRecall.map(percent) ?? "-", decimal(m.reviewMinutesPerHour)]
    }

    static func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }
    static func decimal(_ value: Double) -> String { String(format: "%.2f", value) }
    static func clock(_ seconds: Double) -> String {
        let whole = Int(seconds)
        return String(format: "%d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
    }
}

/// One headline number in two reports.
struct MetricDelta: Equatable, Sendable {
    var label: String
    var before: Double?
    var after: Double?

    var delta: Double? {
        guard let before, let after else { return nil }
        return after - before
    }
}

enum ReportComparison {
    /// Headline metrics for overall and every session present in both reports, in report order.
    static func deltas(from a: EvalReport, to b: EvalReport) -> [MetricDelta] {
        var pairs = [(a.overall, b.overall)]
        for session in a.sessions {
            if let other = b.sessions.first(where: { $0.name == session.name }) { pairs.append((session, other)) }
        }
        return pairs.flatMap { before, after in
            headline.map { name, value in
                MetricDelta(label: "\(before.name) \(name)", before: value(before.metrics), after: value(after.metrics))
            }
        }
    }

    static func render(_ deltas: [MetricDelta]) -> String {
        let width = deltas.map(\.label.count).max() ?? 0
        return deltas.map { d in
            let change = d.delta.map { String(format: "%+.4f", $0) } ?? "n/a"
            let before = d.before.map { String(format: "%.4f", $0) } ?? "-"
            let after = d.after.map { String(format: "%.4f", $0) } ?? "-"
            return "\(d.label.padding(toLength: width, withPad: " ", startingAt: 0))  \(before) -> \(after)  \(change)"
        }.joined(separator: "\n") + "\n"
    }

    private static let headline: [(String, (MetricsReport) -> Double?)] = [
        ("accuracy", { $0.accuracy }),
        ("unflaggedErrorRate", { $0.unflaggedErrorRate }),
        ("flaggedRate", { $0.flaggedRate }),
        ("flagRecall", { $0.flagRecall }),
        ("reviewMinutesPerHour", { $0.reviewMinutesPerHour }),
    ]
}
