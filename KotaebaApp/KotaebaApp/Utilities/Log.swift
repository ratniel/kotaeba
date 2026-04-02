import Foundation
import OSLog

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

struct LogCategory {
    fileprivate let logger: Logger
    fileprivate let name: String

    init(subsystem: String, name: String) {
        self.logger = Logger(subsystem: subsystem, category: name)
        self.name = name
    }

    func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        FileLogger.shared.log(.debug, category: name, message: message)
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        FileLogger.shared.log(.info, category: name, message: message)
    }

    func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        FileLogger.shared.log(.warning, category: name, message: message)
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        FileLogger.shared.log(.error, category: name, message: message)
    }
}

enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.ratniel.KotaebaApp"

    static let app = LogCategory(subsystem: subsystem, name: "app")
    static let audio = LogCategory(subsystem: subsystem, name: "audio")
    static let websocket = LogCategory(subsystem: subsystem, name: "websocket")
    static let server = LogCategory(subsystem: subsystem, name: "server")
    static let setup = LogCategory(subsystem: subsystem, name: "setup")
    static let hotkey = LogCategory(subsystem: subsystem, name: "hotkey")
    static let permissions = LogCategory(subsystem: subsystem, name: "permissions")
    static let textInsertion = LogCategory(subsystem: subsystem, name: "text-insertion")
    static let stats = LogCategory(subsystem: subsystem, name: "stats")
    static let ui = LogCategory(subsystem: subsystem, name: "ui")
}

final class FileLogger {
    static let shared = FileLogger()

    private let queue = DispatchQueue(label: "kotaeba.filelogger", qos: .utility)
    private let dateFormatter = ISO8601DateFormatter()
    private let maxFileSize: UInt64 = 5 * 1024 * 1024
    private let fileURL: URL
    private let isEnabled: Bool

    private init() {
        self.isEnabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        let logsDirectory = Constants.supportDirectory.appendingPathComponent("logs")
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        self.fileURL = logsDirectory.appendingPathComponent("kotaeba.log")
    }

    func log(_ level: LogLevel, category: String, message: String) {
        guard isEnabled else {
            return
        }

        let timestamp = dateFormatter.string(from: Date())
        let line = "\(timestamp) [\(level.rawValue)] [\(category)] \(message)\n"

        queue.async { [fileURL, maxFileSize] in
            self.rotateIfNeeded(fileURL: fileURL, maxFileSize: maxFileSize)
            self.append(line: line, to: fileURL)
        }
    }

    private func append(line: String, to url: URL) {
        guard let data = line.data(using: .utf8) else {
            return
        }

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        do {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            // Avoid recursive logging if file output fails.
        }
    }

    private func rotateIfNeeded(fileURL: URL, maxFileSize: UInt64) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? UInt64,
              fileSize >= maxFileSize else {
            return
        }

        let rotatedURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("kotaeba-\(Int(Date().timeIntervalSince1970)).log")

        do {
            if FileManager.default.fileExists(atPath: rotatedURL.path) {
                try FileManager.default.removeItem(at: rotatedURL)
            }
            try FileManager.default.moveItem(at: fileURL, to: rotatedURL)
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        } catch {
            // Avoid recursive logging if rotation fails.
        }
    }
}
