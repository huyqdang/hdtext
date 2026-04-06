import XCTest
@testable import HDText

final class AudioDeviceManagerTests: XCTestCase {
    func testAvailableInputDevicesReturnsArray() {
        let devices = AudioDeviceManager.availableInputDevices()
        // On CI this may be empty, but it should not crash
        XCTAssertNotNil(devices)
    }

    func testDefaultInputDeviceReturnsValue() {
        let device = AudioDeviceManager.defaultInputDevice()
        // May be nil on headless CI, but should not crash
        if let device = device {
            XCTAssertFalse(device.uid.isEmpty)
            XCTAssertFalse(device.name.isEmpty)
            XCTAssertTrue(device.isInput)
        }
    }

    func testDeviceForUIDReturnsNilForBogusUID() {
        let device = AudioDeviceManager.device(forUID: "nonexistent-uid-12345")
        XCTAssertNil(device)
    }
}
