import XCTest

final class ModelDownloadProgressTests: XCTestCase {
    func testVoiceModelsFillTheFirstShare() {
        XCTAssertEqual(ModelDownloadProgress(model: .voice, phase: .listing, modelFraction: 0).fraction, 0)
        XCTAssertEqual(ModelDownloadProgress(model: .voice, phase: .compiling, modelFraction: 1).fraction, 0.15,
                       accuracy: 1e-9)
    }

    func testTranscriptionModelFillsTheRest() {
        XCTAssertEqual(ModelDownloadProgress(model: .transcription, phase: .listing, modelFraction: 0).fraction, 0.15,
                       accuracy: 1e-9)
        XCTAssertEqual(ModelDownloadProgress(model: .transcription, phase: .downloading(file: 2, of: 4),
                                             modelFraction: 0.5).fraction, 0.575, accuracy: 1e-9)
        XCTAssertEqual(ModelDownloadProgress(model: .transcription, phase: .compiling, modelFraction: 1).fraction, 1)
    }

    func testOutOfRangeFractionsAreClamped() {
        XCTAssertEqual(ModelDownloadProgress(model: .voice, phase: .listing, modelFraction: -1).fraction, 0)
        XCTAssertEqual(ModelDownloadProgress(model: .transcription, phase: .compiling, modelFraction: 7).fraction, 1)
        XCTAssertEqual(ModelDownloadProgress(model: .voice, phase: .listing, modelFraction: .nan).fraction, 0)
    }

    func testLabels() {
        XCTAssertEqual(ModelDownloadProgress(model: .voice, phase: .downloading(file: 2, of: 7), modelFraction: 0.3).label,
                       "Voice models · file 3 of 7")
        XCTAssertEqual(ModelDownloadProgress(model: .transcription, phase: .downloading(file: 7, of: 7),
                                             modelFraction: 1).label,
                       "Transcription model · file 7 of 7")
        XCTAssertEqual(ModelDownloadProgress(model: .transcription, phase: .compiling, modelFraction: 1).label,
                       "Setting up transcription model")
        XCTAssertEqual(ModelDownloadProgress(model: .voice, phase: .listing, modelFraction: 0).label,
                       "Finding voice models")
    }
}
