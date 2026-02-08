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
    private let storeInMemory: Bool
    private(set) var isAvailable = true
    private(set) var lastError: Error?

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

    init(storeInMemory: Bool = false) {
        self.storeInMemory = storeInMemory
        setupModelContainer()
        loadCachedStats()
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

            cachedTotal = AggregatedStats(
                totalWords: cachedTotal.totalWords + wordCount,
                totalDuration: cachedTotal.totalDuration + duration,
                sessionCount: cachedTotal.sessionCount + 1
            )
            persistTotalCache()

            let startOfDay = calendar.startOfDay(for: now)
            if cachedTodayDate != startOfDay {
                resetTodayCache(for: startOfDay)
            }

            cachedToday = AggregatedStats(
                totalWords: cachedToday.totalWords + wordCount,
                totalDuration: cachedToday.totalDuration + duration,
                sessionCount: cachedToday.sessionCount + 1
            )
            persistTodayCache()
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
    func getTodayStats(currentDate: Date = Date()) -> AggregatedStats {
        let startOfDay = calendar.startOfDay(for: currentDate)
        if cachedTodayDate == startOfDay {
            return cachedToday
        }

        let stats = getStats(
            from: startOfDay,
            to: calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        )
        cachedTodayDate = startOfDay
        cachedToday = stats
        persistTodayCache()
        return stats
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
            resetTodayCache(for: Date())
            persistTotalCache()
        } catch {
            Log.stats.error("Failed to clear data: \(error)")
        }
    }
}
