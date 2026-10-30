import Foundation

/// Builds ground truth from each member's own-device recording, so table audio doesn't have to be
/// labeled by ear. Development aid only; the app itself records on one phone.
///
/// Every track is cut into 20 ms frames on the table's timeline (after its sync offset). A frame is
/// speech when its energy clears the track's gate (the same shape as `VoiceEngine.trimSilence`).
/// When several tracks hear speech in one frame, the loudest keeps it; another track keeps it too
/// only when both are above half the loudest frame of any track (real crosstalk, not bleed).
/// Pauses shorter than the hangover are bridged so one sentence stays one interval.
enum LabelGenerator {
    static let frameSeconds = 0.020
    static let hangoverSeconds = 0.300
    /// Matches `trimSilence`: a frame is speech above this share of the track's own peak…
    static let gateShare: Float = 0.08
    /// …and a track whose peak is below this is treated as silent.
    static let silentPeak: Float = 0.005
    /// Two tracks both above this share of the loudest frame count as talking over each other.
    static let overlapShare: Float = 0.5
    /// The sync clap is looked for in this many seconds at the start of each recording.
    static let clapSearchSeconds = 30.0

    /// One member's own recording, already at `sampleRate`.
    struct Track {
        var speaker: String
        var samples: [Float]
        /// Seconds to add to a track timestamp to land on the table recording's timeline.
        var offsetSeconds: Double = 0
    }

    static func intervals(from tracks: [Track], sampleRate: Int) -> [LabeledInterval] {
        let frameLength = Int((Double(sampleRate) * frameSeconds).rounded())
        guard frameLength > 0 else { return [] }

        let energies = tracks.map { frameEnergies($0.samples, frameLength: frameLength) }
        let shifts = tracks.map { Int(($0.offsetSeconds / frameSeconds).rounded()) }
        let gates = energies.map { frames -> Float in
            guard let peak = frames.max(), peak > silentPeak else { return .infinity }
            return peak * gateShare
        }
        let loudest = energies.compactMap { $0.max() }.max() ?? 0

        let frameCount = zip(energies, shifts).map { $0.count + $1 }.max() ?? 0
        var active = Array(repeating: Array(repeating: false, count: max(0, frameCount)), count: tracks.count)
        for frame in 0..<max(0, frameCount) {
            var speaking: [(track: Int, energy: Float)] = []
            for track in tracks.indices {
                let local = frame - shifts[track]
                guard energies[track].indices.contains(local), energies[track][local] > gates[track] else { continue }
                speaking.append((track, energies[track][local]))
            }
            guard let top = speaking.max(by: { $0.energy < $1.energy }) else { continue }
            active[top.track][frame] = true
            if top.energy > loudest * overlapShare {
                for other in speaking where other.energy > loudest * overlapShare {
                    active[other.track][frame] = true
                }
            }
        }

        let hangover = Int((hangoverSeconds / frameSeconds).rounded())
        var result: [LabeledInterval] = []
        for track in tracks.indices {
            for run in runs(in: active[track], bridging: hangover) {
                result.append(LabeledInterval(
                    speaker: tracks[track].speaker,
                    start: Double(run.lowerBound) * frameSeconds,
                    end: Double(run.upperBound) * frameSeconds))
            }
        }
        return result.sorted { ($0.start, $0.speaker) < ($1.start, $1.speaker) }
    }

    /// Offset that lines a track's sync clap up with the table's: the loudest sample near the start of each.
    static func clapOffset(track: [Float], table: [Float], sampleRate: Int) -> Double? {
        guard let inTrack = clapIndex(track, sampleRate: sampleRate),
              let inTable = clapIndex(table, sampleRate: sampleRate) else { return nil }
        return Double(inTable - inTrack) / Double(sampleRate)
    }

    // MARK: Helpers

    /// RMS of each whole frame.
    static func frameEnergies(_ samples: [Float], frameLength: Int) -> [Float] {
        var energies: [Float] = []
        energies.reserveCapacity(samples.count / frameLength)
        var i = 0
        while i + frameLength <= samples.count {
            var sum: Float = 0
            for j in i..<(i + frameLength) { sum += samples[j] * samples[j] }
            energies.append((sum / Float(frameLength)).squareRoot())
            i += frameLength
        }
        return energies
    }

    /// Frame ranges where `flags` is set, joining runs separated by fewer than `bridging` quiet frames.
    private static func runs(in flags: [Bool], bridging: Int) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for (index, on) in flags.enumerated() where on {
            if let last = result.last, index - last.upperBound < bridging {
                result[result.count - 1] = last.lowerBound..<(index + 1)
            } else {
                result.append(index..<(index + 1))
            }
        }
        return result
    }

    private static func clapIndex(_ samples: [Float], sampleRate: Int) -> Int? {
        let window = min(samples.count, Int(clapSearchSeconds * Double(sampleRate)))
        guard window > 0 else { return nil }
        var best = 0
        var bestLevel: Float = 0
        for i in 0..<window where abs(samples[i]) > bestLevel {
            bestLevel = abs(samples[i])
            best = i
        }
        return bestLevel > silentPeak ? best : nil
    }
}
