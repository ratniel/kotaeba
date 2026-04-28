import Foundation

/// Lightweight async command runner shared across setup and model downloads.
enum ShellCommandRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        outputHandler: ((String) -> Void)? = nil
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            if let currentDirectory {
                process.currentDirectoryURL = currentDirectory
            }
            if let environment {
                process.environment = environment
            }

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let outputQueue = DispatchQueue(label: "ShellCommandRunner.output")
            let outputState = CommandOutputState()

            let handleOutput: (Data) -> Void = { data in
                let output = String(decoding: data, as: UTF8.self)
                guard !output.isEmpty else { return }
                outputQueue.sync {
                    outputState.append(output, stream: .standardOutput)
                }
                let lines = output.split(whereSeparator: \.isNewline).map(String.init)
                outputQueue.sync {
                    for line in lines {
                        outputHandler?(line.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }

            let handleError: (Data) -> Void = { data in
                let output = String(decoding: data, as: UTF8.self)
                guard !output.isEmpty else { return }
                outputQueue.sync {
                    outputState.append(output, stream: .standardError)
                }
                let lines = output.split(whereSeparator: \.isNewline).map(String.init)
                outputQueue.sync {
                    for line in lines {
                        outputHandler?(line.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                handleOutput(handle.availableData)
            }
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                handleError(handle.availableData)
            }

            process.terminationHandler = { process in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                handleOutput(outputPipe.fileHandleForReading.readDataToEndOfFile())
                handleError(errorPipe.fileHandleForReading.readDataToEndOfFile())

                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let message = outputQueue.sync {
                        outputState.diagnosticMessage
                    }
                    continuation.resume(throwing: ShellCommandError.commandFailed(message, process.terminationStatus))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

final class CommandOutputState: @unchecked Sendable {
    static let elevatedCharacterLimit = 16_384
    static let tailCharacterLimit = 8_192

    nonisolated(unsafe) private(set) var capturedOutput = ""
    nonisolated(unsafe) private(set) var capturedError = ""
    nonisolated(unsafe) private(set) var outputTail = ""
    nonisolated(unsafe) private(set) var errorTail = ""

    nonisolated(unsafe) var diagnosticMessage: String {
        if !capturedError.isEmpty {
            return capturedError
        }
        if !capturedOutput.isEmpty {
            return capturedOutput
        }
        if !errorTail.isEmpty {
            return errorTail
        }
        if !outputTail.isEmpty {
            return outputTail
        }
        return "Unknown error"
    }

    nonisolated(unsafe) func append(_ output: String, stream: CommandStream) {
        appendToTail(output, stream: stream)

        for line in output.split(whereSeparator: \.isNewline) {
            let text = String(line)
            guard shouldRetainForDiagnostics(text) else { continue }
            appendElevated(text + "\n", stream: stream)
        }
    }

    nonisolated(unsafe) private func appendElevated(_ text: String, stream: CommandStream) {
        switch stream {
        case .standardOutput:
            capturedOutput.append(text)
            capturedOutput = trim(capturedOutput, maxCharacters: Self.elevatedCharacterLimit)
        case .standardError:
            capturedError.append(text)
            capturedError = trim(capturedError, maxCharacters: Self.elevatedCharacterLimit)
        }
    }

    nonisolated(unsafe) private func appendToTail(_ text: String, stream: CommandStream) {
        switch stream {
        case .standardOutput:
            outputTail.append(text)
            outputTail = trim(outputTail, maxCharacters: Self.tailCharacterLimit)
        case .standardError:
            errorTail.append(text)
            errorTail = trim(errorTail, maxCharacters: Self.tailCharacterLimit)
        }
    }

    nonisolated(unsafe) private func trim(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        return String(text.suffix(maxCharacters))
    }

    nonisolated(unsafe) private func shouldRetainForDiagnostics(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }

        let markers = [
            "traceback",
            "exception",
            "error",
            "warn",
            "warning",
            "failed",
            "fatal",
            "unable to",
            "could not",
            "unsupported",
            "not supported"
        ]
        return markers.contains { normalized.contains($0) }
    }
}

enum CommandStream {
    case standardOutput
    case standardError
}

enum ShellCommandError: LocalizedError {
    case commandFailed(String, Int32)

    var commandOutput: String {
        switch self {
        case .commandFailed(let message, _):
            return message
        }
    }

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message, let exitCode):
            return "Command failed (exit \(exitCode)): \(message)"
        }
    }
}

enum ServerEnvironment {
    static func build(model: String? = nil) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["STT_HOST"] = Constants.Server.host
        environment["STT_PORT"] = String(Constants.Server.port)

        if let model {
            environment["STT_MODEL"] = model
        }

        if let token = KeychainSecretStore.string(for: Constants.SecureSettingsKeys.huggingFaceToken),
           !token.isEmpty {
            environment["HF_TOKEN"] = token
            environment["HUGGINGFACE_HUB_TOKEN"] = token
        }

        return environment
    }
}
