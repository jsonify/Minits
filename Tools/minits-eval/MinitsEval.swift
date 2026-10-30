import ArgumentParser
import AVFoundation
import FluidAudio
import Foundation

/// Scores `VoiceEngine` against labeled recordings. See docs/specs/speaker-eval-harness/.
@main
struct MinitsEval: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "minits-eval",
        abstract: "Measure who-said-what accuracy on recorded sessions.",
        subcommands: [Run.self, Label.self, Compare.self])
}

/// Engine output is scored at the same rate the engine reads audio.
private let sampleRate = 16_000

// MARK: run

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Enroll, process table.wav, and score every session in a folder (or one session).")

    @Argument(help: "A session folder, or a folder of session folders.")
    var path: String

    @Option(help: "Below this, a cluster stays Guest.") var acceptSimilarity: Float = VoiceTuning().acceptSimilarity
    @Option(help: "Below this, a line is flagged.") var sureSimilarity: Float = VoiceTuning().sureSimilarity
    @Option(help: "Best vs runner-up gap; smaller is flagged.") var minimumMargin: Float = VoiceTuning().minimumMargin
    @Option(help: "Margin a line needs to override its cluster.") var overrideGap: Float = VoiceTuning().overrideGap

    @Option(help: "Write the JSON report here.") var out: String?

    func run() async throws {
        let tuning = VoiceTuning(acceptSimilarity: acceptSimilarity, sureSimilarity: sureSimilarity,
                                 minimumMargin: minimumMargin, overrideGap: overrideGap)
        let sessions = try SessionFolder.discover(at: URL(fileURLWithPath: path))
        // Check every session before the slow part, so a missing file fails fast.
        let prepared = try sessions.map { ($0, try $0.labels(), try $0.enrollmentSamples()) }

        let engine = VoiceEngine(tuning: tuning)
        try await engine.prepare()

        var scores: [(name: String, score: SessionScore)] = []
        for (session, truth, samples) in prepared {
            log("\(session.name): enrolling \(samples.count) members")
            var voices: [EnrolledVoice] = []
            for (index, sample) in samples.enumerated() {
                let embedding = try await engine.voiceprint(forSampleAt: sample.url)
                voices.append(EnrolledVoice(id: Self.stableID(index), name: sample.member, embedding: embedding))
            }
            log("\(session.name): processing table.wav")
            let processed = try await engine.process(meetingAt: session.tableURL, voices: voices) { _ in }
            let lines = processed.map { line in
                LineUnderTest(start: line.start, end: line.end, text: line.text,
                              speaker: line.speakerID == nil ? nil : line.speakerName,
                              needsReview: line.needsReview, confidence: line.confidence)
            }
            let meetingSeconds = try Self.duration(of: session.tableURL)
            scores.append((session.name, SessionScore(lines: Scorer.score(lines: lines, truth: truth),
                                                      meetingSeconds: meetingSeconds)))
        }

        let report = EvalReport(
            tuning: TuningReport(acceptSimilarity: Self.decimal(acceptSimilarity), sureSimilarity: Self.decimal(sureSimilarity),
                                 minimumMargin: Self.decimal(minimumMargin), overrideGap: Self.decimal(overrideGap)),
            fluidAudioVersion: fluidAudioVersion(),
            sessions: scores)
        print(report.table(), terminator: "")
        if let out {
            try report.encoded().write(to: URL(fileURLWithPath: out))
            log("Wrote \(out)")
        }
    }

    /// The threshold as typed (0.4), not as a widened Float (0.4000000059604645).
    private static func decimal(_ value: Float) -> Double { Double(value.description) ?? Double(value) }

    /// Fixed IDs so a run never depends on random UUIDs.
    private static func stableID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
    }

    private static func duration(of url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.fileFormat.sampleRate
    }
}

// MARK: label

struct Label: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Write labels.json for a session from its tracks/<member>.wav recordings.")

    @Argument(help: "The session folder.")
    var session: String

    func run() async throws {
        let folder = SessionFolder(url: URL(fileURLWithPath: session))
        let config = try folder.config()
        let converter = AudioConverter()
        let table = FileManager.default.fileExists(atPath: folder.tableURL.path)
            ? try converter.resampleAudioFile(folder.tableURL) : nil

        var tracks: [LabelGenerator.Track] = []
        for file in try folder.trackFiles() {
            let samples = try converter.resampleAudioFile(file.url)
            let proposed = table.flatMap { LabelGenerator.clapOffset(track: samples, table: $0, sampleRate: sampleRate) }
            let offset = config.trackOffsetsSeconds[file.member] ?? proposed ?? 0
            let source = config.trackOffsetsSeconds[file.member] != nil ? "session.json"
                : proposed != nil ? "clap" : "none found, using 0"
            log("\(file.member): offset \(String(format: "%.3f", offset)) s (\(source))"
                + (proposed.map { String(format: ", clap proposes %.3f s", $0) } ?? ""))
            tracks.append(LabelGenerator.Track(
                speaker: file.member, samples: LabelGenerator.mutingClap(samples, sampleRate: sampleRate),
                offsetSeconds: offset))
        }

        // Keep hand-marked non-member spans when relabeling.
        let previous = try? folder.labels()
        let truth = GroundTruth(intervals: LabelGenerator.intervals(from: tracks, sampleRate: sampleRate),
                                nonMemberSpans: previous?.nonMemberSpans ?? [])
        try truth.encoded().write(to: folder.labelsURL)
        log("Wrote \(truth.intervals.count) intervals to \(folder.labelsURL.path)")
    }
}

// MARK: compare

struct Compare: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show metric changes from report A to report B.")

    @Argument(help: "The earlier report.") var a: String
    @Argument(help: "The later report.") var b: String

    func run() throws {
        let before = try EvalReport.decode(Data(contentsOf: URL(fileURLWithPath: a)))
        let after = try EvalReport.decode(Data(contentsOf: URL(fileURLWithPath: b)))
        if before.tuning != after.tuning { print("Tuning: \(before.tuning.summary)\n     -> \(after.tuning.summary)\n") }
        print(ReportComparison.render(ReportComparison.deltas(from: before, to: after)), terminator: "")
    }
}

// MARK: Helpers

private func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// The FluidAudio version Xcode resolved, read from the generated project's Package.resolved.
private func fluidAudioVersion() -> String {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let resolved = repo.appendingPathComponent("Minits.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
    struct Resolved: Decodable {
        struct Pin: Decodable {
            struct State: Decodable { var version: String?; var revision: String? }
            var identity: String
            var state: State
        }
        var pins: [Pin]
    }
    guard let data = try? Data(contentsOf: resolved),
          let pin = try? JSONDecoder().decode(Resolved.self, from: data).pins.first(where: { $0.identity == "fluidaudio" })
    else { return "unknown" }
    return pin.state.version ?? pin.state.revision ?? "unknown"
}
