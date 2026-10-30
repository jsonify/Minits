import XCTest

final class LabelGeneratorTests: XCTestCase {
    private let rate = 16_000
    private let frame = LabelGenerator.frameSeconds

    /// Silence with 220 Hz sine bursts at the given (start, end, amplitude) times.
    private func track(seconds: Double, bursts: [(Double, Double, Float)]) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(seconds * Double(rate)))
        for (start, end, amplitude) in bursts {
            for i in Int(start * Double(rate))..<Int(end * Double(rate)) {
                samples[i] = amplitude * sin(2 * .pi * 220 * Float(i) / Float(rate))
            }
        }
        return samples
    }

    private func assertInterval(_ interval: LabeledInterval?, _ speaker: String, _ start: Double, _ end: Double,
                                file: StaticString = #filePath, line: UInt = #line) {
        guard let interval else { return XCTFail("missing \(speaker) interval", file: file, line: line) }
        XCTAssertEqual(interval.speaker, speaker, file: file, line: line)
        XCTAssertEqual(interval.start, start, accuracy: frame, file: file, line: line)
        XCTAssertEqual(interval.end, end, accuracy: frame, file: file, line: line)
    }

    func testBurstsProduceIntervalsWithinOneFrame() {
        let maria = LabelGenerator.Track(speaker: "Maria", samples: track(seconds: 10, bursts: [(1.0, 3.0, 0.5), (6.0, 7.5, 0.5)]))
        let dev = LabelGenerator.Track(speaker: "Dev", samples: track(seconds: 10, bursts: [(3.5, 5.25, 0.4)]))
        let intervals = LabelGenerator.intervals(from: [maria, dev], sampleRate: rate)

        XCTAssertEqual(intervals.count, 3)
        assertInterval(intervals[0], "Maria", 1.0, 3.0)
        assertInterval(intervals[1], "Dev", 3.5, 5.25)
        assertInterval(intervals[2], "Maria", 6.0, 7.5)
    }

    func testShortPauseIsBridgedByHangover() {
        let maria = LabelGenerator.Track(speaker: "Maria", samples: track(seconds: 5, bursts: [(1.0, 2.0, 0.5), (2.2, 3.0, 0.5)]))
        let intervals = LabelGenerator.intervals(from: [maria], sampleRate: rate)
        XCTAssertEqual(intervals.count, 1)
        assertInterval(intervals.first, "Maria", 1.0, 3.0)
    }

    func testOffsetShiftsIntervals() {
        let dev = LabelGenerator.Track(speaker: "Dev", samples: track(seconds: 5, bursts: [(1.0, 2.0, 0.5)]), offsetSeconds: 0.42)
        let intervals = LabelGenerator.intervals(from: [dev], sampleRate: rate)
        assertInterval(intervals.first, "Dev", 1.42, 2.42)
    }

    func testQuietBleedDoesNotCreateInterval() {
        // Dev's device picks up Maria at a tenth of her level; Dev never speaks.
        let maria = LabelGenerator.Track(speaker: "Maria", samples: track(seconds: 5, bursts: [(1.0, 3.0, 0.5)]))
        let dev = LabelGenerator.Track(speaker: "Dev", samples: track(seconds: 5, bursts: [(1.0, 3.0, 0.05)]))
        let intervals = LabelGenerator.intervals(from: [maria, dev], sampleRate: rate)
        XCTAssertEqual(intervals.map(\.speaker), ["Maria"])
    }

    func testSimultaneousLoudBurstsOverlap() {
        let maria = LabelGenerator.Track(speaker: "Maria", samples: track(seconds: 6, bursts: [(1.0, 4.0, 0.5)]))
        let dev = LabelGenerator.Track(speaker: "Dev", samples: track(seconds: 6, bursts: [(3.0, 5.0, 0.45)]))
        let intervals = LabelGenerator.intervals(from: [maria, dev], sampleRate: rate)

        XCTAssertEqual(intervals.count, 2)
        assertInterval(intervals.first { $0.speaker == "Maria" }, "Maria", 1.0, 4.0)
        assertInterval(intervals.first { $0.speaker == "Dev" }, "Dev", 3.0, 5.0)
    }

    func testSilentTrackProducesNothing() {
        let lee = LabelGenerator.Track(speaker: "Lee", samples: [Float](repeating: 0.001, count: rate * 3))
        XCTAssertTrue(LabelGenerator.intervals(from: [lee], sampleRate: rate).isEmpty)
    }

    func testClapSyncProposesOffset() {
        var table = track(seconds: 10, bursts: [(5.0, 6.0, 0.2)])
        var mine = track(seconds: 10, bursts: [(5.0, 6.0, 0.3)])
        table[Int(2.50 * Double(rate))] = 0.9     // clap heard at 2.50 s on the table…
        mine[Int(2.08 * Double(rate))] = 0.95     // …and at 2.08 s on the member's device
        let offset = LabelGenerator.clapOffset(track: mine, table: table, sampleRate: rate)
        XCTAssertEqual(offset ?? .nan, 0.42, accuracy: 1.0 / Double(rate))
    }

    func testMutedClapIsNotLabeled() {
        var mine = track(seconds: 6, bursts: [(4.0, 5.0, 0.3)])
        mine[Int(2.0 * Double(rate))] = 0.95
        let muted = LabelGenerator.mutingClap(mine, sampleRate: rate)
        let intervals = LabelGenerator.intervals(from: [.init(speaker: "Dev", samples: muted)], sampleRate: rate)
        XCTAssertEqual(intervals.count, 1)
        assertInterval(intervals.first, "Dev", 4.0, 5.0)
    }

    func testClapSyncNeedsSound() {
        let silence = [Float](repeating: 0, count: rate)
        XCTAssertNil(LabelGenerator.clapOffset(track: silence, table: silence, sampleRate: rate))
    }
}
