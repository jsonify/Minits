import FluidAudio
import Foundation

/// A member's saved voiceprint, passed into the engine.
struct EnrolledVoice: Sendable {
    let id: UUID
    let name: String
    let embedding: [Float]
}

/// One line of the finished transcript, before it's saved.
struct ProcessedLine: Sendable {
    var start: Double
    var end: Double
    var text: String
    var speakerID: UUID?
    var speakerName: String
    var alternateSpeakerID: UUID?
    var confidence: Double
    var needsReview: Bool
    var reviewNote: String?
}

enum ProcessingStage: Sendable, Equatable {
    case preparingModels
    case findingSpeakers(Double)
    case matchingVoices
    case transcribing
    case assembling

    var label: String {
        switch self {
        case .preparingModels: return "Getting the voice models ready"
        case .findingSpeakers: return "Finding where each voice speaks"
        case .matchingVoices: return "Matching voices to members"
        case .transcribing: return "Writing the transcript"
        case .assembling: return "Putting it together"
        }
    }

    var fraction: Double {
        switch self {
        case .preparingModels: return 0.05
        case .findingSpeakers(let p): return 0.05 + 0.45 * p
        case .matchingVoices: return 0.55
        case .transcribing: return 0.65
        case .assembling: return 0.95
        }
    }
}

/// Tuning knobs for voice matching (cosine similarity of WeSpeaker voiceprints), broken out so the
/// eval CLI can override them without touching `VoiceEngine` itself.
/// Same person usually scores well above 0.5; different people usually below 0.3.
struct VoiceTuning: Sendable {
    var acceptSimilarity: Float = 0.40    // below this, a cluster stays "Guest"
    var sureSimilarity: Float = 0.50      // below this, the line is flagged for review
    var minimumMargin: Float = 0.06       // best vs runner-up gap; smaller gets flagged
    var overrideGap: Float = 0.10         // a line's best match must clear its cluster's score by this to override it
}

enum VoiceEngineError: LocalizedError {
    case sampleTooShort
    case noVoiceFound
    case nothingTranscribed

    var errorDescription: String? {
        switch self {
        case .sampleTooShort: return "That sample was too short or too quiet. Try a full sentence, about 10 seconds, close to the phone."
        case .noVoiceFound: return "Couldn't hear a voice in that sample. Try again a little closer to the phone."
        case .nothingTranscribed: return "No speech was found in the recording."
        }
    }
}

/// Everything that touches FluidAudio lives here. All of it runs on-device; the models are
/// downloaded once on first use and cached in Application Support.
actor VoiceEngine {
    static let shared = VoiceEngine()

    private let tuning: VoiceTuning
    private let sampleRate = 16_000

    private var diarizer: OfflineDiarizerManager?
    private var asr: AsrManager?

    init(tuning: VoiceTuning = VoiceTuning()) {
        self.tuning = tuning
    }

    // MARK: Models

    private func diarizerManager() async throws -> OfflineDiarizerManager {
        if let diarizer { return diarizer }
        var config = OfflineDiarizerConfig.default
        #if os(iOS)
        // Smaller batches keep peak memory around 100 MB so iOS doesn't kill the app.
        config.segmentation.batchSize = 8
        #endif
        let manager = OfflineDiarizerManager(config: config)
        try await manager.prepareModels()
        diarizer = manager
        return manager
    }

    private func asrManager() async throws -> AsrManager {
        if let asr { return asr }
        // v2 is the English-only Parakeet model: better recall on long English meetings.
        let models = try await AsrModels.downloadAndLoad(version: .v2)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        asr = manager
        return manager
    }

    /// Downloads and warms up both models so the first meeting isn't slow.
    func prepare() async throws {
        _ = try await diarizerManager()
        _ = try await asrManager()
    }

    // MARK: Enrollment

    /// Turns a ~10 second "I'm Maria, the chair" recording into a voiceprint.
    func voiceprint(forSampleAt url: URL) async throws -> [Float] {
        let diarizer = try await diarizerManager()
        let samples = try AudioConverter().resampleAudioFile(url)
        let speech = Self.trimSilence(samples, sampleRate: sampleRate)
        guard speech.count >= sampleRate * 2 else { throw VoiceEngineError.sampleTooShort }
        let seconds = Double(speech.count) / Double(sampleRate)
        let embeddings = try await diarizer.embedSpans(
            audioSource: ArrayAudioSampleSource(samples: speech),
            spans: [0..<seconds])
        guard let embedding = embeddings.first, embedding.contains(where: { $0 != 0 }) else {
            throw VoiceEngineError.noVoiceFound
        }
        return embedding
    }

    /// How alike two voiceprints are (−1…1). Used to warn when two members sound similar.
    nonisolated static func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom > 0 ? dot / denom : 0
    }

    // MARK: Meeting processing

    func process(
        meetingAt url: URL,
        voices: [EnrolledVoice],
        progress: @escaping @Sendable (ProcessingStage) -> Void
    ) async throws -> [ProcessedLine] {
        // 1. Who spoke when.
        progress(.preparingModels)
        let diarizer = try await diarizerManager()
        progress(.findingSpeakers(0))
        let result = try await diarizer.process(url) { done, total in
            progress(.findingSpeakers(total > 0 ? Double(done) / Double(total) : 0))
        }
        let segments = result.segments
            .filter { $0.durationSeconds >= 0.3 }
            .sorted { $0.startTimeSeconds < $1.startTimeSeconds }
        guard !segments.isEmpty else { throw VoiceEngineError.nothingTranscribed }

        // 2. Match each voice cluster ("S1", "S2"…) to an enrolled member.
        progress(.matchingVoices)
        var centroids: [String: [Float]] = result.speakerDatabase ?? [:]
        for segment in segments where centroids[segment.speakerId] == nil {
            centroids[segment.speakerId] = segment.embedding
        }
        let clusterToMember = assignClusters(centroids, to: voices)

        // Per-line voiceprints let a single line overrule its cluster when the voice clearly
        // belongs to someone else, and tell us which lines deserve a second look.
        let embeddable = segments.indices.filter { segments[$0].durationSeconds >= 1.0 }
        var lineEmbeddings: [Int: [Float]] = [:]
        if !embeddable.isEmpty, !voices.isEmpty {
            let (source, _) = try AudioSourceFactory().makeDiskBackedSource(from: url, targetSampleRate: sampleRate)
            defer { source.cleanup() }
            let spans = embeddable.map {
                Double(segments[$0].startTimeSeconds)..<Double(segments[$0].endTimeSeconds)
            }
            let vectors = try await diarizer.embedSpans(audioSource: source, spans: spans)
            for (index, vector) in zip(embeddable, vectors) { lineEmbeddings[index] = vector }
        }

        // 3. What was said.
        progress(.transcribing)
        let asr = try await asrManager()
        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        let transcript = try await asr.transcribe(url, decoderState: &state)
        let words = buildWordTimings(from: transcript.tokenTimings ?? [])

        // 4. Stitch words onto speaker segments.
        progress(.assembling)
        var guestNumbers: [String: Int] = [:]
        var drafts: [ProcessedLine] = []
        let wordsBySegment = Self.assign(words: words, to: segments)

        for (index, segment) in segments.enumerated() {
            let text = (wordsBySegment[index] ?? []).map(\.word).joined(separator: " ")
            guard !text.isEmpty else { continue }

            var line = ProcessedLine(
                start: Double(segment.startTimeSeconds), end: Double(segment.endTimeSeconds),
                text: text, speakerID: nil, speakerName: "", alternateSpeakerID: nil,
                confidence: 0, needsReview: false, reviewNote: nil)

            let cluster = clusterToMember[segment.speakerId]
            var chosen = cluster?.id
            var chosenScore = cluster?.score ?? 0

            if let vector = lineEmbeddings[index] {
                let ranked = voices
                    .map { ($0.id, Self.similarity(vector, $0.embedding)) }
                    .sorted { $0.1 > $1.1 }
                if let best = ranked.first {
                    let clusterScore = ranked.first { $0.0 == cluster?.id }?.1 ?? -1
                    if best.1 >= tuning.sureSimilarity, best.1 - clusterScore > tuning.overrideGap {
                        chosen = best.0          // this line clearly sounds like someone else
                    }
                    chosenScore = ranked.first { $0.0 == chosen }?.1 ?? chosenScore
                    let runnerUp = ranked.first { $0.0 != chosen }
                    line.alternateSpeakerID = runnerUp?.0
                    if chosen != nil, let runnerUp, chosenScore - runnerUp.1 < tuning.minimumMargin {
                        line.needsReview = true
                        line.reviewNote = "Two members sound alike here"
                    }
                }
            }

            if let chosen, let voice = voices.first(where: { $0.id == chosen }) {
                line.speakerID = chosen
                line.speakerName = voice.name
                if chosenScore < tuning.sureSimilarity, !line.needsReview {
                    line.needsReview = true
                    line.reviewNote = "Not sure who's speaking"
                }
            } else {
                let number = guestNumbers[segment.speakerId] ?? (guestNumbers.count + 1)
                guestNumbers[segment.speakerId] = number
                line.speakerName = "Guest \(number)"
                line.needsReview = true
                line.reviewNote = "Voice isn't on file"
            }
            line.confidence = Double(max(0, min(1, (chosenScore - 0.2) / 0.6)))
            drafts.append(line)
        }

        guard !drafts.isEmpty else { throw VoiceEngineError.nothingTranscribed }
        return Self.mergeShortTurns(drafts)
    }

    // MARK: Matching helpers

    /// Greedy one-to-one match: the most similar cluster/member pair is locked in first.
    private func assignClusters(
        _ centroids: [String: [Float]], to voices: [EnrolledVoice]
    ) -> [String: (id: UUID, score: Float)] {
        var pairs: [(cluster: String, member: UUID, score: Float)] = []
        for (cluster, centroid) in centroids {
            for voice in voices {
                pairs.append((cluster, voice.id, Self.similarity(centroid, voice.embedding)))
            }
        }
        pairs.sort { $0.score > $1.score }
        var result: [String: (id: UUID, score: Float)] = [:]
        var usedMembers = Set<UUID>()
        for pair in pairs where pair.score >= tuning.acceptSimilarity {
            guard result[pair.cluster] == nil, !usedMembers.contains(pair.member) else { continue }
            result[pair.cluster] = (pair.member, pair.score)
            usedMembers.insert(pair.member)
        }
        return result
    }

    /// Puts each word on the speaker segment it overlaps most, or the nearest one.
    private static func assign(words: [WordTiming], to segments: [TimedSpeakerSegment]) -> [Int: [WordTiming]] {
        var result: [Int: [WordTiming]] = [:]
        var cursor = 0
        for word in words {
            let mid = (word.startTime + word.endTime) / 2
            while cursor < segments.count - 1, Double(segments[cursor].endTimeSeconds) < mid,
                  Double(segments[cursor + 1].startTimeSeconds) <= mid {
                cursor += 1
            }
            // Check the neighbors for the closest segment to this word.
            var bestIndex = cursor
            var bestDistance = Double.infinity
            for index in max(0, cursor - 1)...min(segments.count - 1, cursor + 1) {
                let s = Double(segments[index].startTimeSeconds), e = Double(segments[index].endTimeSeconds)
                let distance = mid < s ? s - mid : (mid > e ? mid - e : 0)
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
            }
            result[bestIndex, default: []].append(word)
        }
        return result
    }

    /// Joins back-to-back pieces from the same person into one readable line.
    private static func mergeShortTurns(_ lines: [ProcessedLine]) -> [ProcessedLine] {
        var merged: [ProcessedLine] = []
        for line in lines {
            if var last = merged.last,
               last.speakerName == line.speakerName,
               line.start - last.end < 1.5,
               !last.needsReview, !line.needsReview,
               last.text.count + line.text.count < 600 {
                last.end = line.end
                last.text += " " + line.text
                last.confidence = min(last.confidence, line.confidence)
                merged[merged.count - 1] = last
            } else {
                merged.append(line)
            }
        }
        return merged
    }

    /// Drops quiet lead-in and trailing silence from a voice sample.
    private static func trimSilence(_ samples: [Float], sampleRate: Int) -> [Float] {
        let frame = sampleRate / 50  // 20 ms
        guard samples.count > frame * 4 else { return samples }
        var energies: [Float] = []
        var i = 0
        while i + frame <= samples.count {
            var sum: Float = 0
            for j in i..<(i + frame) { sum += samples[j] * samples[j] }
            energies.append((sum / Float(frame)).squareRoot())
            i += frame
        }
        guard let peak = energies.max(), peak > 0.005 else { return [] }
        let threshold = peak * 0.08
        guard let first = energies.firstIndex(where: { $0 > threshold }),
              let last = energies.lastIndex(where: { $0 > threshold }) else { return [] }
        let start = max(0, (first - 10) * frame)               // keep ~200 ms padding
        let end = min(samples.count, (last + 11) * frame)
        return Array(samples[start..<end])
    }
}
