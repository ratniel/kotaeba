import Foundation
import SwiftData

/// Manages statistics tracking and persistence
///
/// Uses SwiftData to store session data and compute aggregated statistics.
class StatisticsManager {

    static let shared = StatisticsManager()
    
    // MARK: - Properties
    
    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?
    private let defaults = UserDefaults.standard
    private let calendar = Calendar.current

    private struct CacheKeys {
        static let version = "statsCacheVersion"
        static let totalWords = "statsTotalWords"
        static let totalDuration = "statsTotalDuration"
        static let sessionCount = "statsSessionCount"
        static let todayDate = "statsTodayDate"
        static let todayWords = "statsTodayWords"
        static let todayDuration = "statsTodayDuration"
        static let todaySessionCount = "statsTodaySessionCount"
    }

    private let cacheVersion = 1
    private var cachedTotal: AggregatedStats = .empty
    private var cachedToday: AggregatedStats = .empty
    private var cachedTodayDate: Date?
    
    // MARK: - Initialization
    
    private init() {
        setupModelContainer()
        loadCachedStats()
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

    private func loadCachedStats() {
        let version = defaults.integer(forKey: CacheKeys.version)
        if version != cacheVersion {
            rebuildCaches()
            return
        }

        cachedTotal = AggregatedStats(
            totalWords: defaults.integer(forKey: CacheKeys.totalWords),
            totalDuration: defaults.double(forKey: CacheKeys.totalDuration),
            sessionCount: defaults.integer(forKey: CacheKeys.sessionCount)
        )

        let storedDate = defaults.object(forKey: CacheKeys.todayDate) as? Date
        if let storedDate, calendar.isDateInToday(storedDate) {
            cachedTodayDate = storedDate
            cachedToday = AggregatedStats(
                totalWords: defaults.integer(forKey: CacheKeys.todayWords),
                totalDuration: defaults.double(forKey: CacheKeys.todayDuration),
                sessionCount: defaults.integer(forKey: CacheKeys.todaySessionCount)
            )
        } else {
            resetTodayCache(for: Date())
        }

        if cachedTotal.sessionCount == 0, hasAnySessions() {
            rebuildCaches()
        }
    }

    private func hasAnySessions() -> Bool {
        guard let context = modelContext else { return false }
        do {
            var descriptor = FetchDescriptor<TranscriptionSession>()
            descriptor.fetchLimit = 1
            let sessions = try context.fetch(descriptor)
            return !sessions.isEmpty
        } catch {
            Log.stats.error("Failed to check sessions: \(error)")
            return false
        }
    }

    private func persistTotalCache() {
        defaults.set(cacheVersion, forKey: CacheKeys.version)
        defaults.set(cachedTotal.totalWords, forKey: CacheKeys.totalWords)
        defaults.set(cachedTotal.totalDuration, forKey: CacheKeys.totalDuration)
        defaults.set(cachedTotal.sessionCount, forKey: CacheKeys.sessionCount)
    }

    private func persistTodayCache() {
        defaults.set(cachedTodayDate, forKey: CacheKeys.todayDate)
        defaults.set(cachedToday.totalWords, forKey: CacheKeys.todayWords)
        defaults.set(cachedToday.totalDuration, forKey: CacheKeys.todayDuration)
        defaults.set(cachedToday.sessionCount, forKey: CacheKeys.todaySessionCount)
    }

    private func resetTodayCache(for date: Date) {
        cachedTodayDate = date
        cachedToday = .empty
        persistTodayCache()
    }

    private func rebuildCaches() {
        guard let context = modelContext else {
            cachedTotal = .empty
            cachedToday = .empty
            cachedTodayDate = Date()
            persistTotalCache()
            persistTodayCache()
            return
        }

        do {
            let descriptor = FetchDescriptor<TranscriptionSession>()
            let sessions = try context.fetch(descriptor)

            let startOfDay = calendar.startOfDay(for: Date())
            var totalWords = 0
            var totalDuration: TimeInterval = 0
            var totalSessions = 0
            var todayWords = 0
            var todayDuration: TimeInterval = 0
            var todaySessions = 0

            for session in sessions {
                totalWords += session.wordCount
                totalDuration += session.duration
                totalSessions += 1

                if session.startTime >= startOfDay {
                    todayWords += session.wordCount
                    todayDuration += session.duration
                    todaySessions += 1
                }
            }

            cachedTotal = AggregatedStats(
                totalWords: totalWords,
                totalDuration: totalDuration,
                sessionCount: totalSessions
            )
            cachedToday = AggregatedStats(
                totalWords: todayWords,
                totalDuration: todayDuration,
                sessionCount: todaySessions
            )
            cachedTodayDate = Date()
            persistTotalCache()
            persistTodayCache()
        } catch {
            Log.stats.error("Failed to rebuild stats cache: \(error)")
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

            cachedTotal = AggregatedStats(
                totalWords: cachedTotal.totalWords + wordCount,
                totalDuration: cachedTotal.totalDuration + duration,
                sessionCount: cachedTotal.sessionCount + 1
            )
            persistTotalCache()

            let sessionDate = session.startTime
            if let cachedTodayDate, calendar.isDate(cachedTodayDate, inSameDayAs: sessionDate) == false {
                resetTodayCache(for: sessionDate)
            } else if cachedTodayDate == nil {
                resetTodayCache(for: sessionDate)
            }

            if calendar.isDate(sessionDate, inSameDayAs: cachedTodayDate ?? sessionDate) {
                cachedToday = AggregatedStats(
                    totalWords: cachedToday.totalWords + wordCount,
                    totalDuration: cachedToday.totalDuration + duration,
                    sessionCount: cachedToday.sessionCount + 1
                )
                persistTodayCache()
            }
        } catch {
            Log.stats.error("Failed to save session: \(error)")
        }
    }
    
    // MARK: - Statistics Retrieval
    
    /// Get aggregated statistics for all sessions
    func getAggregatedStats() -> AggregatedStats {
        if cachedTotal.sessionCount == 0, hasAnySessions() {
            rebuildCaches()
        }
        return cachedTotal
    }
    
    /// Get statistics for today
    func getTodayStats() -> AggregatedStats {
        if let cachedTodayDate, calendar.isDateInToday(cachedTodayDate) {
            return cachedToday
        }
        rebuildCaches()
        return cachedToday
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
            cachedTotal = .empty
            cachedToday = .empty
            cachedTodayDate = Date()
            persistTotalCache()
            persistTodayCache()
        } catch {
            Log.stats.error("Failed to clear data: \(error)")
        }
    }
}
