import Foundation
import SwiftData

/// Manages statistics tracking and persistence
///
/// Uses SwiftData to store session data and compute aggregated statistics.
class StatisticsManager {
    
    // MARK: - Properties
    
    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?
    private var cachedTodayStats: AggregatedStats?
    private var cachedTodayStartOfDay: Date?
    private let storeInMemory: Bool
    private(set) var isAvailable = true
    private(set) var lastError: Error?
    
    // MARK: - Initialization
    
    init(storeInMemory: Bool = false) {
        self.storeInMemory = storeInMemory
        setupModelContainer()
    }
    
    private func setupModelContainer() {
        do {
            let schema = Schema([TranscriptionSession.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: storeInMemory)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            
            if let container = modelContainer {
                modelContext = ModelContext(container)
            }
            isAvailable = true
            lastError = nil
        } catch {
            Log.stats.error("Failed to setup model container: \(error)")
            isAvailable = false
            lastError = error
        }
    }
    
    // MARK: - Session Recording
    
    /// Record a completed transcription session
    func recordSession(
        wordCount: Int,
        duration: TimeInterval,
        text: String? = nil,
        language: String = "en",
        now: Date = Date()
    ) {
        guard let context = modelContext else {
            Log.stats.error("Model context not available")
            return
        }
        
        let session = TranscriptionSession(
            startTime: now.addingTimeInterval(-duration),
            endTime: now,
            wordCount: wordCount,
            duration: duration,
            transcribedText: text,
            language: language
        )
        
        context.insert(session)
        
        do {
            try context.save()
            Log.stats.info("Session recorded: \(wordCount) words, \(Int(duration))s")
            updateTodayCacheIfNeeded(with: wordCount, duration: duration, now: now)
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
    func getTodayStats(currentDate: Date = Date()) -> AggregatedStats {
        guard let context = modelContext else {
            return .empty
        }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: currentDate)
        if cachedTodayStartOfDay != startOfDay {
            cachedTodayStartOfDay = startOfDay
            cachedTodayStats = nil
        }

        if let cached = cachedTodayStats {
            return cached
        }
        
        do {
            let predicate = #Predicate<TranscriptionSession> { session in
                session.startTime >= startOfDay
            }
            let descriptor = FetchDescriptor<TranscriptionSession>(predicate: predicate)
            let sessions = try context.fetch(descriptor)
            
            let totalWords = sessions.reduce(0) { $0 + $1.wordCount }
            let totalDuration = sessions.reduce(0.0) { $0 + $1.duration }
            
            let stats = AggregatedStats(
                totalWords: totalWords,
                totalDuration: totalDuration,
                sessionCount: sessions.count
            )
            cachedTodayStats = stats
            return stats
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
            cachedTodayStats = nil
            cachedTodayStartOfDay = nil
        } catch {
            Log.stats.error("Failed to clear data: \(error)")
        }
    }

    private func updateTodayCacheIfNeeded(with wordCount: Int, duration: TimeInterval, now: Date) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)

        if cachedTodayStartOfDay != startOfDay {
            cachedTodayStartOfDay = startOfDay
            cachedTodayStats = nil
        }

        if let cached = cachedTodayStats {
            cachedTodayStats = AggregatedStats(
                totalWords: cached.totalWords + wordCount,
                totalDuration: cached.totalDuration + duration,
                sessionCount: cached.sessionCount + 1
            )
        }
    }
}
