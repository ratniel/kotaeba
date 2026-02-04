import Foundation
import SwiftData

/// Manages statistics tracking and persistence
///
/// Uses SwiftData to store session data and compute aggregated statistics.
class StatisticsManager {
    
    // MARK: - Properties
    
    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?
    
    // MARK: - Initialization
    
    init() {
        setupModelContainer()
    }
    
    private func setupModelContainer() {
        do {
            let schema = Schema([TranscriptionSession.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            
            if let container = modelContainer {
                modelContext = ModelContext(container)
            }
        } catch {
            Log.stats.error("Failed to setup model container: \(error)")
        }
    }
    
    // MARK: - Session Recording
    
    /// Record a completed transcription session
    func recordSession(wordCount: Int, duration: TimeInterval, text: String? = nil, language: String = "en") {
        guard let context = modelContext else {
            Log.stats.error("Model context not available")
            return
        }
        
        let session = TranscriptionSession(
            startTime: Date().addingTimeInterval(-duration),
            endTime: Date(),
            wordCount: wordCount,
            duration: duration,
            transcribedText: text,
            language: language
        )
        
        context.insert(session)
        
        do {
            try context.save()
            Log.stats.info("Session recorded: \(wordCount) words, \(Int(duration))s")
        } catch {
            Log.stats.error("Failed to save session: \(error)")
        }
    }
    
    // MARK: - Statistics Retrieval
    
    /// Get aggregated statistics for all sessions
    func getAggregatedStats() -> AggregatedStats {
        guard let context = modelContext else {
            return .empty
        }
        
        do {
            let descriptor = FetchDescriptor<TranscriptionSession>()
            let sessions = try context.fetch(descriptor)
            
            let totalWords = sessions.reduce(0) { $0 + $1.wordCount }
            let totalDuration = sessions.reduce(0.0) { $0 + $1.duration }
            
            return AggregatedStats(
                totalWords: totalWords,
                totalDuration: totalDuration,
                sessionCount: sessions.count
            )
        } catch {
            Log.stats.error("Failed to fetch sessions: \(error)")
            return .empty
        }
    }
    
    /// Get statistics for today
    func getTodayStats() -> AggregatedStats {
        guard let context = modelContext else {
            return .empty
        }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        
        do {
            let predicate = #Predicate<TranscriptionSession> { session in
                session.startTime >= startOfDay
            }
            let descriptor = FetchDescriptor<TranscriptionSession>(predicate: predicate)
            let sessions = try context.fetch(descriptor)
            
            let totalWords = sessions.reduce(0) { $0 + $1.wordCount }
            let totalDuration = sessions.reduce(0.0) { $0 + $1.duration }
            
            return AggregatedStats(
                totalWords: totalWords,
                totalDuration: totalDuration,
                sessionCount: sessions.count
            )
        } catch {
            Log.stats.error("Failed to fetch today's sessions: \(error)")
            return .empty
        }
    }
    
    /// Get statistics for a specific date range
    func getStats(from startDate: Date, to endDate: Date) -> AggregatedStats {
        guard let context = modelContext else {
            return .empty
        }
        
        do {
            let predicate = #Predicate<TranscriptionSession> { session in
                session.startTime >= startDate && session.startTime <= endDate
            }
            let descriptor = FetchDescriptor<TranscriptionSession>(predicate: predicate)
            let sessions = try context.fetch(descriptor)
            
            let totalWords = sessions.reduce(0) { $0 + $1.wordCount }
            let totalDuration = sessions.reduce(0.0) { $0 + $1.duration }
            
            return AggregatedStats(
                totalWords: totalWords,
                totalDuration: totalDuration,
                sessionCount: sessions.count
            )
        } catch {
            Log.stats.error("Failed to fetch sessions for range: \(error)")
            return .empty
        }
    }
    
    /// Get recent sessions (for history display)
    func getRecentSessions(limit: Int = 10) -> [TranscriptionSession] {
        guard let context = modelContext else {
            return []
        }
        
        do {
            var descriptor = FetchDescriptor<TranscriptionSession>(
                sortBy: [SortDescriptor(\.startTime, order: .reverse)]
            )
            descriptor.fetchLimit = limit
            return try context.fetch(descriptor)
        } catch {
            Log.stats.error("Failed to fetch recent sessions: \(error)")
            return []
        }
    }
    
    // MARK: - Data Management
    
    /// Clear all session data
    func clearAllData() {
        guard let context = modelContext else { return }
        
        do {
            try context.delete(model: TranscriptionSession.self)
            try context.save()
            Log.stats.info("All data cleared")
        } catch {
            Log.stats.error("Failed to clear data: \(error)")
        }
    }
}
