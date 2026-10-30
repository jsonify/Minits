import XCTest

final class TimeSpanTests: XCTestCase {
    func testOverlapOfPartiallyCoveringSpans() {
        let a = TimeSpan(start: 0, end: 10)
        let b = TimeSpan(start: 6, end: 15)
        XCTAssertEqual(a.overlap(with: b), 4, accuracy: 1e-9)
    }

    func testOverlapOfDisjointSpansIsZero() {
        let a = TimeSpan(start: 0, end: 5)
        let b = TimeSpan(start: 6, end: 9)
        XCTAssertEqual(a.overlap(with: b), 0)
    }

    func testDurationNeverNegative() {
        XCTAssertEqual(TimeSpan(start: 5, end: 3).duration, 0)
    }
}
