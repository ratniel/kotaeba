import XCTest
@testable import KotaebaApp

final class AudioInputDeviceSelectionTests: XCTestCase {
    private let builtIn = AudioInputDevice(
        id: "built-in",
        name: "MacBook Pro Microphone",
        isAvailable: true,
        isSystemDefault: false
    )
    private let usb = AudioInputDevice(
        id: "usb-mic",
        name: "USB Microphone",
        isAvailable: true,
        isSystemDefault: false
    )

    func testSystemDefaultSelectionDoesNotResolvePhysicalDevice() {
        let resolvedID = AudioInputDeviceSelection.resolvedCaptureDeviceID(
            selectedID: AudioInputDevice.systemDefaultID,
            availableDevices: [.systemDefault, builtIn, usb]
        )

        XCTAssertNil(resolvedID)
    }

    func testAvailableSelectedDeviceResolvesForCapture() {
        let resolvedID = AudioInputDeviceSelection.resolvedCaptureDeviceID(
            selectedID: usb.id,
            availableDevices: [.systemDefault, builtIn, usb]
        )

        XCTAssertEqual(resolvedID, usb.id)
    }

    func testUnavailableSelectedDeviceFallsBackToSystemDefaultForCapture() {
        let resolvedID = AudioInputDeviceSelection.resolvedCaptureDeviceID(
            selectedID: "missing-mic",
            availableDevices: [.systemDefault, builtIn, usb]
        )

        XCTAssertNil(resolvedID)
    }

    func testUnavailableSelectedDeviceRemainsVisibleInSettings() {
        let devices = AudioInputDeviceSelection.devicesForSettings(
            availablePhysicalDevices: [usb, builtIn],
            selectedID: "missing-mic",
            selectedDisplayName: "Desk Mic"
        )

        XCTAssertEqual(devices.first, .systemDefault)
        XCTAssertTrue(devices.contains(usb))
        XCTAssertTrue(devices.contains(builtIn))
        XCTAssertEqual(devices.last?.id, "missing-mic")
        XCTAssertEqual(devices.last?.settingsDisplayName, "Desk Mic (Unavailable)")
    }
}
