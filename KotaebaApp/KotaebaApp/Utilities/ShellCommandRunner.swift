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
            var capturedError = ""

            let handleOutput: (Data) -> Void = { data in
                guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
                let lines = output.split(whereSeparator: \.isNewline).map(String.init)
                outputQueue.sync {
                    for line in lines {
                        outputHandler?(line.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }

            let handleError: (Data) -> Void = { data in
                guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
                outputQueue.sync {
                    capturedError.append(output)
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

                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let message = capturedError.isEmpty ? "Unknown error" : capturedError
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

enum ShellCommandError: LocalizedError {
    case commandFailed(String, Int32)

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
