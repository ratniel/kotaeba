import Foundation

struct AudioInputDevice: Identifiable, Equatable {
    static let systemDefaultID = "system-default"
    static let systemDefault = AudioInputDevice(
        id: systemDefaultID,
        name: "System Default",
        isAvailable: true,
        isSystemDefault: true
    )

    let id: String
    let name: String
    let isAvailable: Bool
    let isSystemDefault: Bool

    var settingsDisplayName: String {
        if isSystemDefault {
            return name
        }

        if isAvailable {
            return name
        }

        return "\(name) (Unavailable)"
    }
}

enum AudioInputDeviceSelection {
    static func normalizedSelectionID(_ rawID: String?) -> String {
        let trimmedID = rawID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedID.isEmpty ? AudioInputDevice.systemDefaultID : trimmedID
    }

    static func resolvedCaptureDeviceID(
        selectedID rawSelectedID: String?,
        availableDevices: [AudioInputDevice]
    ) -> String? {
        let selectedID = normalizedSelectionID(rawSelectedID)
        guard selectedID != AudioInputDevice.systemDefaultID else { return nil }

        let selectedDevice = availableDevices.first { device in
            device.id == selectedID && device.isAvailable && !device.isSystemDefault
        }

        return selectedDevice?.id
    }

    static func devicesForSettings(
        availablePhysicalDevices: [AudioInputDevice],
        selectedID rawSelectedID: String?,
        selectedDisplayName: String? = nil
    ) -> [AudioInputDevice] {
        let selectedID = normalizedSelectionID(rawSelectedID)
        let sortedDevices = availablePhysicalDevices
            .filter { !$0.isSystemDefault }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        var devices = [AudioInputDevice.systemDefault]
        devices.append(contentsOf: sortedDevices)

        if selectedID != AudioInputDevice.systemDefaultID,
           !sortedDevices.contains(where: { $0.id == selectedID }) {
            devices.append(
                AudioInputDevice(
                    id: selectedID,
                    name: selectedDisplayName ?? "Previously Selected Microphone",
                    isAvailable: false,
                    isSystemDefault: false
                )
            )
        }

        return devices
    }
}
