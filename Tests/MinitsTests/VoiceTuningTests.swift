import XCTest

final class VoiceTuningTests: XCTestCase {
    func testDefaultsMatchTodaysConstants() {
        let tuning = VoiceTuning()
        XCTAssertEqual(tuning.acceptSimilarity, 0.40)
        XCTAssertEqual(tuning.sureSimilarity, 0.50)
        XCTAssertEqual(tuning.minimumMargin, 0.06)
        XCTAssertEqual(tuning.overrideGap, 0.10)
    }
}
