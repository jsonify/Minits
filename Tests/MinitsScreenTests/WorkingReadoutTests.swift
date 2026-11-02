@testable import Minits
import XCTest

/// The playful words and the creeping percentage on the working readout (`WorkingLCD`).
final class WorkingReadoutTests: XCTestCase {
    func testWordsAreUniqueAndShort() {
        XCTAssertEqual(Set(WorkingWords.all).count, WorkingWords.all.count)
        for word in WorkingWords.all {
            XCTAssertFalse(word.isEmpty)
            XCTAssertLessThanOrEqual(word.count, 26, "\(word) fits on one LCD line")
        }
    }

    func testWordsRotateEveryFewSeconds() {
        let first = WorkingWords.word(at: 0)
        XCTAssertEqual(WorkingWords.word(at: WorkingWords.secondsPerWord - 0.1), first)
        XCTAssertNotEqual(WorkingWords.word(at: WorkingWords.secondsPerWord), first)
        let lap = WorkingWords.secondsPerWord * Double(WorkingWords.all.count)
        XCTAssertEqual(WorkingWords.word(at: lap), first, "wraps around")
        XCTAssertEqual(WorkingWords.word(at: 0, offset: -1), WorkingWords.all.last, "a negative offset wraps too")
    }

    func testProgressCreepsTowardTheCeilingWithoutReachingIt() {
        let start = WorkingProgress.shown(fraction: 0.5, ceiling: 0.95, since: 0, tau: 30)
        let later = WorkingProgress.shown(fraction: 0.5, ceiling: 0.95, since: 30, tau: 30)
        let muchLater = WorkingProgress.shown(fraction: 0.5, ceiling: 0.95, since: 3_600, tau: 30)
        XCTAssertEqual(start, 0.5)
        XCTAssertGreaterThan(later, start)
        XCTAssertGreaterThan(muchLater, later)
        XCTAssertLessThan(muchLater, 0.95)
    }

    func testProgressNeverFallsBelowTheRealValue() {
        XCTAssertEqual(WorkingProgress.shown(fraction: 0.6, ceiling: 0.4, since: 100, tau: 10), 0.6)
        XCTAssertEqual(WorkingProgress.shown(fraction: 0.6, ceiling: 0.9, since: 100, tau: 0), 0.6)
    }
}
