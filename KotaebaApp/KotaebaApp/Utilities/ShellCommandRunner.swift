import Foundation

enum ShellCommandError: LocalizedError {
    case invalidCommand
    case nonZeroExit(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidCommand:
            return "Invalid command."
        case .nonZeroExit(let code):
            return "Command exited with status \(code)."
        }
    }
}

struct ShellCommandRunner {
    static func run(
        command: String,
        currentDirectory: URL? = nil,
        onOutput: ((String) -> Void)? = nil
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                onOutput?(output)
            }
        }

        try process.run()
        await process.waitUntilExit()
        outputPipe.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            throw ShellCommandError.nonZeroExit(process.terminationStatus)
        }
    }

    static func run(
        executableURL: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        onOutput: ((String) -> Void)? = nil
    ) async throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                onOutput?(output)
            }
        }

        try process.run()
        await process.waitUntilExit()
        outputPipe.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            throw ShellCommandError.nonZeroExit(process.terminationStatus)
        }
    }
}
