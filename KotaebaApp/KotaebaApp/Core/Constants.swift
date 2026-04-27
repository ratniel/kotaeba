import Foundation
import SwiftUI

// MARK: - App Constants

enum Constants {
    
    // MARK: - App Info
    static let appName = "Kotaeba"
    static let appVersion = "1.0.0"
    static let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Kotaeba")
    static var isRunningTests: Bool { Runtime.isRunningTests }

    enum Runtime {
        static let isRunningTests =
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            NSClassFromString("XCTestCase") != nil
    }

    enum FeatureFlags {
        static var defaultDiagnosticsUI: Bool {
            if let environmentOverride = ProcessInfo.processInfo.environment["KOTAEBA_SHOW_DIAGNOSTICS"] {
                return environmentOverride == "1"
            }
            return true
        }

        static var showDiagnosticsUI: Bool {
            if UserDefaults.standard.object(forKey: UserDefaultsKeys.showDiagnosticsUI) != nil {
                return UserDefaults.standard.bool(forKey: UserDefaultsKeys.showDiagnosticsUI)
            }
            return defaultDiagnosticsUI
        }
    }
    
    // MARK: - Server
    enum Server {
        static let defaultHost = "localhost"
        static let defaultPort = 9999
        static var host: String {
            let stored = UserDefaults.standard.string(forKey: UserDefaultsKeys.serverHost)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let stored, !stored.isEmpty {
                return stored
            }
            return defaultHost
        }
        static var port: Int {
            let stored = UserDefaults.standard.integer(forKey: UserDefaultsKeys.serverPort)
            if (1...65535).contains(stored) {
                return stored
            }
            return defaultPort
        }
        static let websocketPath = "/v1/audio/transcriptions/realtime"
        static var websocketURL: URL {
            URL(string: "ws://\(host):\(port)\(websocketPath)")!
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

    // MARK: - Models
    enum Models {
        struct Model: Codable, Equatable {
            let name: String
            let identifier: String
            let description: String
            let languageCoverage: String
            let size: String
            let speedLabel: String
            let qualityLabel: String

            enum CodingKeys: String, CodingKey {
                case name
                case identifier
                case description
                case languageCoverage = "language_coverage"
                case size
                case speedLabel = "speed_label"
                case qualityLabel = "quality_label"
            }

            init(
                name: String,
                identifier: String,
                description: String,
                languageCoverage: String,
                size: String,
                speedLabel: String,
                qualityLabel: String
            ) {
                self.name = name
                self.identifier = identifier
                self.description = description
                self.languageCoverage = languageCoverage
                self.size = size
                self.speedLabel = speedLabel
                self.qualityLabel = qualityLabel
            }

            var summary: String {
                "\(speedLabel) • \(qualityLabel) • \(size)"
            }
        }

        static let currentQwenIdentifier = "Qwen/Qwen3-ASR-1.7B"
        static let legacyQwenIdentifier = "mlx-community/Qwen3-ASR-0.6B-8bit"
        static let catalog = ModelCatalogLoader.load()
        static var availableModels: [Model] {
            mergedModels(bundledModels: catalog.models, customModels: CustomModelCatalogStore.loadModels())
        }
        static var defaultModel: Model { catalog.defaultModel }

        static func model(withIdentifier identifier: String) -> Model? {
            availableModels.first(where: { $0.identifier == normalizedIdentifier(identifier) })
        }

        static func isValidIdentifier(_ identifier: String) -> Bool {
            ModelCatalogLoader.isValidModelIdentifier(identifier)
        }

        static func mergedModels(bundledModels: [Model], customModels: [Model]) -> [Model] {
            var seenIdentifiers = Set<String>()
            var models: [Model] = []

            for model in bundledModels + customModels {
                let normalizedIdentifier = normalizedIdentifier(model.identifier)
                guard !seenIdentifiers.contains(normalizedIdentifier) else { continue }
                seenIdentifiers.insert(normalizedIdentifier)
                models.append(model)
            }

            return models
        }

        static func normalizedIdentifier(_ identifier: String) -> String {
            switch identifier {
            case legacyQwenIdentifier:
                return currentQwenIdentifier
            default:
                return identifier
            }
        }

        static func isQwenModelIdentifier(_ identifier: String) -> Bool {
            normalizedIdentifier(identifier) == currentQwenIdentifier
        }

        static func startupValidationMessage(for model: Model, rawError: String) -> String {
            if isQwenModelIdentifier(model.identifier),
               rawError.contains("ModelConfig.__init__()") {
                return "\(model.name) could not be loaded because the current MLX runtime misclassifies Qwen ASR and does not include a usable STT backend for it yet. Use \(defaultModel.name) or Whisper Large V3 Turbo for now."
            }

            if isQwenModelIdentifier(model.identifier),
               rawError.contains("Model type None not supported") {
                return "\(model.name) was routed through the STT path, but the installed MLX runtime still has no qwen3_asr STT implementation. Use \(defaultModel.name) or Whisper Large V3 Turbo for now."
            }

            if isQwenModelIdentifier(model.identifier),
               (rawError.contains("does not recognize this architecture") || rawError.contains("qwen3_asr")) {
                return "\(model.name) was found successfully, but the bundled Transformers and MLX runtime stack does not understand the qwen3_asr architecture yet. Use \(defaultModel.name) or Whisper Large V3 Turbo for now."
            }

            return "\(model.name) failed validation during server startup. Open Test App for full diagnostics."
        }
    }
    
    // MARK: - Hotkey
    enum Hotkey {
        static let defaultKeyCode: UInt16 = 7  // 'x' key
        static let defaultModifiers: HotkeyModifiers = .control
        static let escapeKeyCode: UInt16 = 53
        static let minimumHoldDuration: TimeInterval = 0.18
        static let doubleTapLockWindow: TimeInterval = 0.45
        static let defaultDisplayString = HotkeyShortcut.default.displayString
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
        static let mainWindowWidth: CGFloat = 760
        static let mainWindowHeight: CGFloat = 640
        
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
        static let setupCompletedKey = "setupCompleted"
        static let developmentVenvPath = supportDirectory.appendingPathComponent(".venv")
        static let developmentPythonPath = developmentVenvPath.appendingPathComponent("bin/python")
        static let venvPath = developmentVenvPath
        static let bundledRuntimeFolderName = "Runtime"
        static let bundledRuntimeProjectFolderName = "PythonRuntime"
        static let bundledPythonRelativePaths = [
            "\(bundledRuntimeFolderName)/bin/python3",
            "\(bundledRuntimeFolderName)/bin/python",
            "\(bundledRuntimeFolderName)/.venv/bin/python",
            "python/bin/python3",
            "python/bin/python"
        ]

        enum RuntimeSource {
            case bundled
            case developmentFallback
            case unavailable

            var displayName: String {
                switch self {
                case .bundled:
                    return "Bundled app runtime"
                case .developmentFallback:
                    return "Development runtime"
                case .unavailable:
                    return "Runtime unavailable"
                }
            }
        }

        static func resolvedPythonPath(bundle: Bundle = .main) -> URL? {
            let fileManager = FileManager.default

            if let resourceURL = bundle.resourceURL {
                for relativePath in bundledPythonRelativePaths {
                    let candidate = resourceURL.appendingPathComponent(relativePath)
                    if fileManager.isExecutableFile(atPath: candidate.path) {
                        return candidate
                    }
                }
            }

            if fileManager.isExecutableFile(atPath: developmentPythonPath.path) {
                return developmentPythonPath
            }

            return nil
        }

        static func runtimeSource(bundle: Bundle = .main) -> RuntimeSource {
            guard let pythonPath = resolvedPythonPath(bundle: bundle) else {
                return .unavailable
            }

            if pythonPath.path.hasPrefix(supportDirectory.path) {
                return .developmentFallback
            }

            return .bundled
        }

        static var pythonPath: URL? {
            resolvedPythonPath()
        }

        static var isRuntimeAvailable: Bool {
            pythonPath != nil
        }

        static var runtimeDisplayPath: String {
            pythonPath?.path ?? expectedBundledRuntimeLocation.path
        }

        static var runtimeSourceDisplayName: String {
            runtimeSource().displayName
        }

        static var expectedBundledRuntimeLocation: URL {
            (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent(bundledRuntimeFolderName)
        }

        static var bundledRuntimeProjectLocation: URL {
            (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent(bundledRuntimeProjectFolderName)
        }
    }

    // MARK: - UserDefaults Keys
    enum UserDefaultsKeys {
        static let recordingMode = "recordingMode"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let serverHost = "serverHost"
        static let serverPort = "serverPort"
        static let serverPortMigrationVersion = "serverPortMigrationVersion"
        static let autoStartServer = "autoStartServer"
        static let launchAtLogin = "launchAtLogin"
        static let useClipboardFallback = "useClipboardFallback"
        static let safeModeEnabled = "safeModeEnabled"
        static let showDiagnosticsUI = "showDiagnosticsUI"
        static let selectedAudioDevice = "selectedAudioDevice"
        static let selectedModel = "selectedModel"
        static let customModels = "customModels"
        static let didAutoDownloadDefaultModel = "didAutoDownloadDefaultModel"
    }

    // MARK: - Secure Settings Keys
    enum SecureSettingsKeys {
        static let huggingFaceToken = "HF_TOKEN"
    }
}

enum SettingsMigration {
    private static let legacyLocalhostPort = 8000
    static let currentVersion = 3
    private static let loopbackHosts = ["localhost", "127.0.0.1"]

    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        let migrationVersion = defaults.integer(forKey: Constants.UserDefaultsKeys.serverPortMigrationVersion)
        guard migrationVersion < currentVersion else { return }

        defer {
            defaults.set(currentVersion, forKey: Constants.UserDefaultsKeys.serverPortMigrationVersion)
        }

        migrateLocalhostPortIfNeeded(defaults: defaults)
        migrateUnsupportedQwenIdentifierIfNeeded(defaults: defaults)
        migrateAudioInputSelectionIfNeeded(defaults: defaults)
    }

    private static func migrateLocalhostPortIfNeeded(defaults: UserDefaults) {
        guard defaults.object(forKey: Constants.UserDefaultsKeys.serverPort) != nil else { return }
        guard defaults.integer(forKey: Constants.UserDefaultsKeys.serverPort) == legacyLocalhostPort else { return }

        let storedHost = defaults.string(forKey: Constants.UserDefaultsKeys.serverHost)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? Constants.Server.defaultHost
        guard loopbackHosts.contains(storedHost) else { return }

        defaults.set(Constants.Server.defaultPort, forKey: Constants.UserDefaultsKeys.serverPort)
    }

    private static func migrateUnsupportedQwenIdentifierIfNeeded(defaults: UserDefaults) {
        guard let selectedModel = defaults.string(forKey: Constants.UserDefaultsKeys.selectedModel) else { return }
        guard Constants.Models.isQwenModelIdentifier(selectedModel) else { return }

        defaults.set(Constants.Models.defaultModel.identifier, forKey: Constants.UserDefaultsKeys.selectedModel)
    }

    private static func migrateAudioInputSelectionIfNeeded(defaults: UserDefaults) {
        let selectedDeviceID = defaults.string(forKey: Constants.UserDefaultsKeys.selectedAudioDevice)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard selectedDeviceID?.isEmpty != false else { return }
        defaults.set(AudioInputDevice.systemDefaultID, forKey: Constants.UserDefaultsKeys.selectedAudioDevice)
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
        case .hold: return "Hold the hotkey while speaking, or double-tap to lock dictation"
        case .toggle: return "Press hotkey to start, press again to stop"
        }
    }
}

// MARK: - Model Download Status

enum ModelDownloadStatus {
    case unknown
    case checking
    case downloading
    case downloaded
    case notDownloaded

    var displayText: String {
        switch self {
        case .unknown: return "Unknown"
        case .checking: return "Checking..."
        case .downloading: return "Downloading..."
        case .downloaded: return "Downloaded"
        case .notDownloaded: return "Not Downloaded"
        }
    }

    var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .checking: return "arrow.clockwise"
        case .downloading: return "arrow.down.circle.fill"
        case .downloaded: return "checkmark.circle.fill"
        case .notDownloaded: return "arrow.down.circle"
        }
    }

    var color: Color {
        switch self {
        case .unknown: return Constants.UI.textSecondary
        case .checking: return Constants.UI.accentOrange
        case .downloading: return Constants.UI.accentOrange
        case .downloaded: return Constants.UI.successGreen
        case .notDownloaded: return Constants.UI.textSecondary
        }
    }
}

// MARK: - Model Preflight

enum ModelPreflightState: Equatable {
    case idle
    case checkingCache
    case downloading
    case validatingCustomModel
    case validatingAndStartingServer

    static func resolve(appState: AppState, downloadStatus: ModelDownloadStatus) -> ModelPreflightState {
        if appState == .serverStarting {
            return .validatingAndStartingServer
        }

        switch downloadStatus {
        case .checking:
            return .checkingCache
        case .downloading:
            return .downloading
        case .unknown, .downloaded, .notDownloaded:
            return .idle
        }
    }

    var locksModelSelection: Bool {
        self != .idle
    }

    var selectionLockMessage: String? {
        switch self {
        case .idle:
            return nil
        case .checkingCache:
            return "Checking the selected model before allowing another change."
        case .downloading:
            return "Downloading the selected model before allowing another change."
        case .validatingCustomModel:
            return "Validating a custom model before allowing another change."
        case .validatingAndStartingServer:
            return "Validating the selected model before allowing another change."
        }
    }
}

enum CustomModelValidationStatus: Equatable {
    case idle
    case checkingRepository
    case validatingCompatibility
    case saving

    var isRunning: Bool {
        self != .idle
    }

    var displayText: String {
        switch self {
        case .idle:
            return ""
        case .checkingRepository:
            return "Checking Hugging Face"
        case .validatingCompatibility:
            return "Validating model"
        case .saving:
            return "Saving model"
        }
    }
}

// MARK: - Server Startup

enum ServerStartupStage: Equatable {
    case preparingRuntime
    case validatingModel
    case launchingServer

    var title: String {
        switch self {
        case .preparingRuntime:
            return "Preparing runtime..."
        case .validatingModel:
            return "Validating model..."
        case .launchingServer:
            return "Starting server..."
        }
    }

    func detail(modelName: String) -> String {
        switch self {
        case .preparingRuntime:
            return "Preparing speech runtime..."
        case .validatingModel:
            return "Checking model: \(modelName)"
        case .launchingServer:
            return "Launching local transcription server..."
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
