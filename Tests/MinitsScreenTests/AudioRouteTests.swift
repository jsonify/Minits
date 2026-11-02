@testable import Minits
import XCTest

final class AudioRouteTests: XCTestCase {
    private typealias Output = AudioRoute.Output

    func testThePhoneItselfIsNotNamed() {
        XCTAssertNil(AudioRoute.deviceName(of: [Output(name: "Speaker", isPhone: true)]))
        XCTAssertNil(AudioRoute.deviceName(of: [Output(name: "Receiver", isPhone: true)]))
        XCTAssertNil(AudioRoute.deviceName(of: []))
    }

    func testAnotherDeviceIsNamed() {
        XCTAssertEqual(AudioRoute.deviceName(of: [Output(name: "Car Audio", isPhone: false)]), "Car Audio")
        XCTAssertEqual(AudioRoute.deviceName(of: [Output(name: "Speaker", isPhone: true),
                                                  Output(name: " AirPods Pro ", isPhone: false)]), "AirPods Pro")
    }

    func testAnUnnamedDeviceStillShows() {
        XCTAssertEqual(AudioRoute.deviceName(of: [Output(name: "  ", isPhone: false)]), "another device")
    }

    func testNote() {
        XCTAssertEqual(AudioRoute.note(deviceName: "Car Audio"),
                       "Sound is playing on Car Audio. Use the AirPlay key to play it on this iPhone.")
    }

    func testAFixedRouteKeepsItsDevice() {
        XCTAssertEqual(AudioRoute(deviceName: "Car Audio").deviceName, "Car Audio")
        XCTAssertNil(AudioRoute(deviceName: nil).deviceName)
    }
}
