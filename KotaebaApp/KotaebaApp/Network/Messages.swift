import Foundation

// MARK: - Client → Server Messages

/// Configuration sent to server when connection is established
struct ClientConfig: Codable {
    let model: String
    let language: String
    let sampleRate: Int
    let channels: Int
    let vadEnabled: Bool
    let vadAggressiveness: Int
    
    enum CodingKeys: String, CodingKey {
        case model
        case language
        case sampleRate = "sample_rate"
        case channels
        case vadEnabled = "vad_enabled"
        case vadAggressiveness = "vad_aggressiveness"
    }
    
    /// Default configuration for mlx-audio Whisper
    static let `default` = ClientConfig(
        model: "mlx-community/whisper-large-v3-mlx",
        language: "en",
        sampleRate: Int(Constants.Audio.sampleRate),
        channels: Int(Constants.Audio.channels),
        vadEnabled: true,
        vadAggressiveness: 3
    )
}

// MARK: - Server → Client Messages

/// Transcription result from server
struct ServerTranscription: Codable {
    let text: String
    let segments: [TranscriptionSegment]?
    let isPartial: Bool
    let language: String?
    let confidence: Double?
    
    enum CodingKeys: String, CodingKey {
        case text
        case segments
        case isPartial = "is_partial"
        case language
        case confidence
    }
    
    /// Check if this is a final (non-partial) transcription
    var isFinal: Bool {
        !isPartial
    }
}

/// Segment within a transcription (with timing info)
struct TranscriptionSegment: Codable {
    let start: Double?
    let end: Double?
    let text: String?
}

/// Status message from server
struct ServerStatus: Codable {
    let status: String
    let message: String
    let timestamp: String?
    let progress: Double?
}

// MARK: - Message Parsing

/// Unified enum for all server messages
enum ServerMessage {
    case transcription(ServerTranscription)
    case status(ServerStatus)
    case unknown(String)
    
    /// Parse a JSON string into a ServerMessage
    init(from jsonString: String) {
        guard let data = jsonString.data(using: .utf8) else {
            self = .unknown(jsonString)
            return
        }
        
        // Try parsing as transcription first (has "text" field)
        if let transcription = try? JSONDecoder().decode(ServerTranscription.self, from: data) {
            self = .transcription(transcription)
            return
        }
        
        // Try parsing as status (has "status" field)
        if let status = try? JSONDecoder().decode(ServerStatus.self, from: data) {
            self = .status(status)
            return
        }
        
        // Unknown message format
        self = .unknown(jsonString)
    }
}
