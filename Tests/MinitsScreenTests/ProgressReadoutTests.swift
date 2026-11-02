@testable import Minits
import XCTest

/// The steps and percentages the working readout shows while a meeting is processed and while a write-up is drafted.
final class ProgressReadoutTests: XCTestCase {
    func testProcessingStagesOnlyMoveForward() {
        let stages: [ProcessingStage] = [
            .preparingModels, .findingSpeakers(0), .findingSpeakers(0.5), .findingSpeakers(1), .matchingVoices,
            .transcribing(0), .transcribing(0.25), .transcribing(1), .assembling,
        ]
        for (earlier, later) in zip(stages, stages.dropFirst()) {
            XCTAssertLessThanOrEqual(earlier.fraction, later.fraction, "\(earlier) → \(later)")
            XCTAssertLessThanOrEqual(earlier.step, later.step)
        }
        XCTAssertEqual(stages.last?.step, ProcessingStage.stepCount)
    }

    func testTranscriptionMovesAcrossItsShare() {
        XCTAssertEqual(ProcessingStage.transcribing(0).fraction, 0.50, accuracy: 1e-9)
        XCTAssertEqual(ProcessingStage.transcribing(0.5).fraction, 0.725, accuracy: 1e-9)
        XCTAssertEqual(ProcessingStage.transcribing(1).fraction, 0.95, accuracy: 1e-9)
        XCTAssertEqual(ProcessingStage.transcribing(7).fraction, 0.95, accuracy: 1e-9, "clamped")
    }

    func testEachStageCeilingIsAtOrAboveWhereItIs() {
        let stages: [ProcessingStage] = [.preparingModels, .findingSpeakers(0.3), .matchingVoices, .transcribing(0.6),
                                         .assembling]
        for stage in stages {
            XCTAssertGreaterThanOrEqual(stage.ceiling, stage.fraction, "\(stage)")
            XCTAssertLessThan(stage.ceiling, 1, "\(stage) never shows 100% before it's done")
        }
    }

    func testFinishedWindowsCountsEachWindowOnce() {
        let windows = FinishedWindows()
        XCTAssertEqual(windows.finish(2), 1)
        XCTAssertEqual(windows.finish(0), 2)
        XCTAssertEqual(windows.finish(2), 2, "reported twice")
        XCTAssertEqual(windows.finish(1), 3)
    }

    func testDraftProgressReadsThenWrites() {
        let parts = 3
        let steps = (0..<parts).map { DraftProgress.reading(part: $0, of: parts) }
            + [DraftProgress.writing(.adHoc, afterParts: parts)]
        XCTAssertEqual(steps.map(\.step), [1, 2, 3, 4])
        XCTAssertTrue(steps.allSatisfy { $0.stepCount == 4 })
        XCTAssertEqual(steps[0].label, "Reading part 1 of 3")
        XCTAssertEqual(steps[3].label, "Writing the summary")
        XCTAssertEqual(DraftProgress.writing(.board, afterParts: 1).label, "Writing the minutes")
        for (earlier, later) in zip(steps, steps.dropFirst()) {
            XCTAssertEqual(earlier.ceiling, later.fraction, accuracy: 1e-9, "each step ends where the next starts")
        }
        XCTAssertEqual(steps[3].ceiling, 0.97, accuracy: 1e-9)
    }
}
