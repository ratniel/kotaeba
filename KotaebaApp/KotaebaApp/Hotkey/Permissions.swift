import ApplicationServices
import AVFoundation
import AppKit

/// Utility for checking and requesting system permissions
///
/// Required permissions:
/// - Accessibility: For global hotkeys and text insertion
/// - Microphone: For audio capture
struct PermissionManager {
    private static let accessibilityPromptCooldown: TimeInterval = 3
    private static var lastAccessibilityPromptDate: Date?
    private static var lastLoggedAccessibilityTrust: Bool?
    private static var hasRequestedAccessibilityPromptThisLaunch = false
    
    // MARK: - Accessibility Permission

    static var runningAppURL: URL {
        Bundle.main.bundleURL.resolvingSymlinksInPath()
    }

    static var runningAppPath: String {
        runningAppURL.path
    }

    static var runningAppName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? Constants.appName
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    static var isRunningFromDerivedData: Bool {
        runningAppPath.contains("/DerivedData/")
    }
    
    /// Check if Accessibility permission is granted
    static func checkAccessibilityPermission() -> Bool {
        refreshAccessibilityPermission(source: "check")
    }

    /// Refresh Accessibility permission and emit lightweight diagnostics when it changes.
    @discardableResult
    static func refreshAccessibilityPermission(source: String) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let trustedWithoutPrompt = AXIsProcessTrustedWithOptions(options as CFDictionary)
        let trustedLegacyCheck = AXIsProcessTrusted()
        let isTrusted = trustedWithoutPrompt || trustedLegacyCheck

        if trustedWithoutPrompt != trustedLegacyCheck {
            Log.permissions.warning(
                """
                Accessibility trust mismatch from \(source). \
                withOptions=\(trustedWithoutPrompt), legacy=\(trustedLegacyCheck), \
                bundleID=\(bundleIdentifier), appPath=\(runningAppPath)
                """
            )
        }

        if lastLoggedAccessibilityTrust != isTrusted {
            Log.permissions.info(
                """
                Accessibility trust changed to \(isTrusted) from \(source). \
                bundleID=\(bundleIdentifier), appPath=\(runningAppPath)
                """
            )
            lastLoggedAccessibilityTrust = isTrusted
        } else {
            Log.permissions.debug("Accessibility trust rechecked from \(source): \(isTrusted)")
        }

        return isTrusted
    }
    
    /// Request Accessibility permission (shows system dialog)
    @discardableResult
    static func requestAccessibilityPermission(forcePrompt: Bool = true) -> Bool {
        let currentlyTrusted = refreshAccessibilityPermission(source: "request")
        Log.permissions.info("Accessibility currently trusted: \(currentlyTrusted)")

        guard !currentlyTrusted else {
            return true
        }

        guard forcePrompt else {
            return false
        }

        if hasRequestedAccessibilityPromptThisLaunch {
            Log.permissions.info("Accessibility prompt already shown this launch; opening Settings instead")
            openAccessibilitySettings()
            return false
        }

        let now = Date()
        if let lastAccessibilityPromptDate,
           now.timeIntervalSince(lastAccessibilityPromptDate) < accessibilityPromptCooldown {
            Log.permissions.info("Skipping duplicate accessibility prompt within cooldown window")
            return false
        }

        hasRequestedAccessibilityPromptThisLaunch = true
        lastAccessibilityPromptDate = now
        Log.permissions.info("Requesting accessibility permission (opening System Settings)...")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        return false
    }
    
    /// Open System Settings to Accessibility pane
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Reveal the currently running app bundle so the exact build can be granted in System Settings.
    static func revealRunningAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([runningAppURL])
    }
    
    // MARK: - Microphone Permission
    
    /// Check if Microphone permission is granted
    static func checkMicrophonePermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    /// Request Microphone permission
    static func requestMicrophonePermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Request Microphone permission if needed, otherwise open settings
    static func requestMicrophonePermissionOrOpenSettings() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        Log.permissions.info("Microphone authorization status: \(status.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")
        switch status {
        case .notDetermined:
            Log.permissions.info("Showing microphone permission dialog...")
            let result = await AVCaptureDevice.requestAccess(for: .audio)
            Log.permissions.info("User responded to mic dialog: \(result)")
            return result
        case .authorized:
            Log.permissions.info("Already authorized")
            return true
        case .denied, .restricted:
            Log.permissions.warning("Denied/restricted - opening Settings...")
            openMicrophoneSettings()
            return false
        @unknown default:
            Log.permissions.warning("Unknown status - opening Settings...")
            openMicrophoneSettings()
            return false
        }
    }
    
    /// Open System Settings to Microphone pane
    static func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - Combined Check
    
    /// Check if all required permissions are granted
    static func checkAllPermissions() -> Bool {
        checkAccessibilityPermission() && checkMicrophonePermission()
    }
    
    /// Get status of all permissions
    static func getPermissionStatus(source: String = "status") -> PermissionStatus {
        PermissionStatus(
            accessibility: refreshAccessibilityPermission(source: source),
            microphone: checkMicrophonePermission()
        )
    }
}

/// Status of all required permissions
struct PermissionStatus: Equatable {
    let accessibility: Bool
    let microphone: Bool
    
    var allGranted: Bool {
        accessibility && microphone
    }
    
    var missingPermissions: [String] {
        var missing: [String] = []
        if !accessibility { missing.append("Accessibility") }
        if !microphone { missing.append("Microphone") }
        return missing
    }
}
