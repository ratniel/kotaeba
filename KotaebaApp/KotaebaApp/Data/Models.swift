import Foundation
import SwiftData

/// Represents a single transcription session
///
/// A session starts when recording begins and ends when recording stops.
/// Tracks words spoken and duration for statistics.
@Model
final class TranscriptionSession {
    /// Unique identifier
    var id: UUID
    
    /// When the session started
    var startTime: Date
    
    /// When the session ended (nil if still active)
    var endTime: Date?
    
    /// Number of words transcribed in this session
    var wordCount: Int
    
    /// Duration in seconds
    var duration: TimeInterval
    
    /// The transcribed text (optional, for history)
    var transcribedText: String?
    
    /// Language used for transcription
    var language: String
    
    init(
        id: UUID = UUID(),
        startTime: Date = Date(),
        endTime: Date? = nil,
        wordCount: Int = 0,
        duration: TimeInterval = 0,
        transcribedText: String? = nil,
        language: String = "en"
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.wordCount = wordCount
        self.duration = duration
        self.transcribedText = transcribedText
        self.language = language
    }
}

/// Aggregated statistics computed from sessions
struct AggregatedStats {
    /// Total words spoken across all sessions
    let totalWords: Int
    
    /// Total time spent talking (in seconds)
    let totalDuration: TimeInterval
    
    /// Number of sessions
    let sessionCount: Int
    
    /// Estimated time saved (based on typing vs speaking speed)
    var estimatedTimeSaved: TimeInterval {
        // Average typing: 40 WPM, speaking: 150 WPM
        // Time to type = words / 40 minutes
        // Time to speak = words / 150 minutes
        // Time saved = (1/40 - 1/150) * words minutes
        //            = words * 0.0183 minutes
        //            = words * 1.1 seconds
        Double(totalWords) * Constants.Stats.secondsSavedPerWord
    }
    
    /// Format total duration as readable string
    var formattedDuration: String {
        formatDuration(totalDuration)
    }
    
    /// Format time saved as readable string
    var formattedTimeSaved: String {
        formatDuration(estimatedTimeSaved)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
    
    static let empty = AggregatedStats(
        totalWords: 0,
        totalDuration: 0,
        sessionCount: 0
    )
}
