import ApplicationServices
import AVFoundation
import AppKit

/// Utility for checking and requesting system permissions
///
/// Required permissions:
/// - Accessibility: For global hotkeys and text insertion
/// - Microphone: For audio capture
struct PermissionManager {
    
    // MARK: - Accessibility Permission
    
    /// Check if Accessibility permission is granted
    static func checkAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }
    
    /// Request Accessibility permission (shows system dialog)
    static func requestAccessibilityPermission() {
        let currentlyTrusted = AXIsProcessTrusted()
        print("[PermissionManager] Accessibility currently trusted: \(currentlyTrusted)")
        if !currentlyTrusted {
            print("[PermissionManager] Requesting accessibility permission (opening System Settings)...")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
    }
    
    /// Open System Settings to Accessibility pane
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
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
        print("[PermissionManager] Microphone authorization status: \(status.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")
        switch status {
        case .notDetermined:
            print("[PermissionManager] Showing microphone permission dialog...")
            let result = await AVCaptureDevice.requestAccess(for: .audio)
            print("[PermissionManager] User responded to mic dialog: \(result)")
            return result
        case .authorized:
            print("[PermissionManager] Already authorized")
            return true
        case .denied, .restricted:
            print("[PermissionManager] Denied/restricted - opening Settings...")
            openMicrophoneSettings()
            return false
        @unknown default:
            print("[PermissionManager] Unknown status - opening Settings...")
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
    static func getPermissionStatus() -> PermissionStatus {
        PermissionStatus(
            accessibility: checkAccessibilityPermission(),
            microphone: checkMicrophonePermission()
        )
    }
}

/// Status of all required permissions
struct PermissionStatus {
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
