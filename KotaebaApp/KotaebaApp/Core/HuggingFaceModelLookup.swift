import Foundation

enum HuggingFaceModelLookupError: Error, LocalizedError, Equatable {
    case invalidIdentifier(String)
    case invalidResponse
    case notFound(String)
    case unauthorized(String)
    case notSpeechToTextModel(String)
    case serverRejected(Int)

    var errorDescription: String? {
        switch self {
        case .invalidIdentifier(let identifier):
            return "Enter a Hugging Face model ID like owner/model-name. \(identifier) is not valid."
        case .invalidResponse:
            return "Hugging Face returned an unexpected response."
        case .notFound(let identifier):
            return "Hugging Face could not find \(identifier)."
        case .unauthorized(let identifier):
            return "\(identifier) is private or unavailable with the stored Hugging Face token."
        case .notSpeechToTextModel(let identifier):
            return "\(identifier) does not advertise a speech-to-text model type on Hugging Face."
        case .serverRejected(let statusCode):
            return "Hugging Face rejected the model check with HTTP \(statusCode)."
        }
    }
}

enum HuggingFaceModelLookup {
    static func fetchModelInfo(identifier: String, token: String?) async throws -> HuggingFaceModelInfo {
        let normalizedIdentifier = Constants.Models.normalizedIdentifier(
            identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard Constants.Models.isValidIdentifier(normalizedIdentifier) else {
            throw HuggingFaceModelLookupError.invalidIdentifier(identifier)
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.path = "/api/models/\(normalizedIdentifier)"

        guard let url = components.url else {
            throw HuggingFaceModelLookupError.invalidIdentifier(identifier)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HuggingFaceModelLookupError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let info = try JSONDecoder().decode(HuggingFaceModelInfo.self, from: data)
            guard Constants.Models.isValidIdentifier(info.id) else {
                throw HuggingFaceModelLookupError.invalidIdentifier(info.id)
            }
            return HuggingFaceModelInfo(
                id: Constants.Models.normalizedIdentifier(info.id),
                pipelineTag: info.pipelineTag,
                tags: info.tags
            )
        case 401, 403:
            throw HuggingFaceModelLookupError.unauthorized(normalizedIdentifier)
        case 404:
            throw HuggingFaceModelLookupError.notFound(normalizedIdentifier)
        default:
            throw HuggingFaceModelLookupError.serverRejected(httpResponse.statusCode)
        }
    }

    static func validateSpeechToTextCandidate(_ info: HuggingFaceModelInfo) throws {
        let normalizedTags = Set(info.tags.map { $0.lowercased() })
        let hasSpeechToTextTag = normalizedTags.contains("automatic-speech-recognition") ||
            normalizedTags.contains("audio-to-text") ||
            normalizedTags.contains("speech-to-text")
        let pipelineTag = info.pipelineTag?.lowercased() ?? ""
        let isSpeechToTextPipeline = pipelineTag == "automatic-speech-recognition"

        guard isSpeechToTextPipeline || hasSpeechToTextTag else {
            throw HuggingFaceModelLookupError.notSpeechToTextModel(info.id)
        }
    }
}
