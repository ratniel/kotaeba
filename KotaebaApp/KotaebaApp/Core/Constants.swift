import Foundation
import SwiftUI

// MARK: - App Constants

enum Constants {
    
    // MARK: - App Info
    static let appName = "Kotaeba"
    static let appVersion = "1.0.0"
    static let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Kotaeba")
    
    // MARK: - Server
    enum Server {
        static let host = "localhost"
        static let port = 8765
        static let websocketPath = "/v1/audio/transcriptions/realtime"
        static var websocketURL: URL {
            URL(string: "ws://\(host):\(port)\(websocketPath)")!
        }
        static var healthURL: URL {
            URL(string: "http://\(host):\(port)/health")!
        }
        static let healthCheckInterval: TimeInterval = 5.0
        static let startupTimeout: TimeInterval = 30.0
    }
    
    // MARK: - Audio
    enum Audio {
        static let sampleRate: Double = 16000
        static let channels: UInt32 = 1
        static let bufferSize: UInt32 = 1600  // 100ms at 16kHz
        static let format = "pcmInt16"
    }
    
    // MARK: - Hotkey
    enum Hotkey {
        static let defaultKeyCode: UInt16 = 7  // 'x' key
        static let defaultModifiers: UInt32 = 1 << 18  // Control key
        static let defaultDisplayString = "⌃X"
    }
    
    // MARK: - UI
    enum UI {
        // Colors (dark mode optimized)
        static let backgroundDark = Color(hex: "1C1C1E")
        static let surfaceDark = Color(hex: "2C2C2E")
        static let accentOrange = Color(hex: "FF6B35")
        static let textPrimary = Color.white
        static let textSecondary = Color(hex: "8E8E93")
        static let successGreen = Color(hex: "30D158")
        static let recordingRed = Color(hex: "FF453A")
        
        // Recording Bar
        static let recordingBarHeight: CGFloat = 48
        static let recordingBarCornerRadius: CGFloat = 12
        static let recordingBarPadding: CGFloat = 16
        
        // Main Window
        static let mainWindowWidth: CGFloat = 480
        static let mainWindowHeight: CGFloat = 600
        
        // Visualizer
        static let visualizerBarCount = 12
        static let visualizerBarWidth: CGFloat = 4
        static let visualizerBarSpacing: CGFloat = 3
        static let visualizerMaxHeight: CGFloat = 24
    }
    
    // MARK: - Statistics
    enum Stats {
        // Average typing: 40 WPM, speaking: 150 WPM
        // Time saved per word ≈ 1.1 seconds
        static let secondsSavedPerWord: Double = 1.1
    }
    
    // MARK: - Setup
    enum Setup {
        static let venvPath = supportDirectory.appendingPathComponent(".venv")
        static let setupCompletedKey = "setupCompleted"
        static let pythonPath = venvPath.appendingPathComponent("bin/python")
    }
    
    // MARK: - UserDefaults Keys
    enum UserDefaultsKeys {
        static let recordingMode = "recordingMode"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let language = "language"
        static let autoStartServer = "autoStartServer"
        static let launchAtLogin = "launchAtLogin"
        static let useClipboardFallback = "useClipboardFallback"
        static let selectedAudioDevice = "selectedAudioDevice"
    }
}

// MARK: - Recording Mode

enum RecordingMode: String, CaseIterable, Codable {
    case hold = "hold"      // Push-to-talk: hold key to record
    case toggle = "toggle"  // Press to start, press again to stop
    
    var displayName: String {
        switch self {
        case .hold: return "Hold to Record"
        case .toggle: return "Toggle Recording"
        }
    }
    
    var description: String {
        switch self {
        case .hold: return "Hold the hotkey while speaking, release to stop"
        case .toggle: return "Press hotkey to start, press again to stop"
        }
    }
}

// MARK: - App State

enum AppState: Equatable {
    case idle
    case serverStarting
    case serverRunning
    case connecting
    case recording
    case processing
    case error(String)
    
    var isRecording: Bool {
        self == .recording
    }
    
    var canRecord: Bool {
        self == .serverRunning || self == .idle
    }
    
    var statusText: String {
        switch self {
        case .idle: return "Server not running"
        case .serverStarting: return "Starting server..."
        case .serverRunning: return "Ready"
        case .connecting: return "Connecting..."
        case .recording: return "Recording..."
        case .processing: return "Processing..."
        case .error(let msg): return "Error: \(msg)"
        }
    }
    
    var statusColor: Color {
        switch self {
        case .idle: return Constants.UI.textSecondary
        case .serverStarting, .connecting, .processing: return Constants.UI.accentOrange
        case .serverRunning: return Constants.UI.successGreen
        case .recording: return Constants.UI.recordingRed
        case .error: return Constants.UI.recordingRed
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
