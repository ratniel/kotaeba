import Foundation
import SwiftData

/// Manages statistics tracking and persistence
///
/// Uses SwiftData to store session data and compute aggregated statistics.
class StatisticsManager {

    static let shared = StatisticsManager(storeInMemory: Constants.Runtime.isRunningTests)

    // MARK: - Properties

    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?
    private let cacheDefaults: UserDefaults?
    private let storeInMemory: Bool
    private var inMemorySessions: [InMemorySession] = []
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

    private struct InMemorySession {
        let startTime: Date
        let endTime: Date?
        let wordCount: Int
        let duration: TimeInterval
        let transcribedText: String?
        let language: String
    }

    private let cacheVersion = 1
    private var cachedTotal: AggregatedStats = .empty
    private var cachedToday: AggregatedStats = .empty
    private var cachedTodayDate: Date?
    private var calendar: Calendar { .current }

    // MARK: - Initialization

    init(storeInMemory: Bool = false) {
        self.storeInMemory = storeInMemory
        self.cacheDefaults = storeInMemory ? nil : UserDefaults.standard
        setupModelContainer()
        loadCachedStats()
    }

    private func setupModelContainer() {
        guard !storeInMemory else {
            modelContainer = nil
            modelContext = nil
            isAvailable = true
            lastError = nil
            return
        }

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
        guard let defaults = cacheDefaults else {
            cachedTotal = .empty
            cachedTodayDate = calendar.startOfDay(for: Date())
            cachedToday = .empty
            return
        }

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
        if storeInMemory {
            return !inMemorySessions.isEmpty
        }

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
        guard let defaults = cacheDefaults else { return }
        defaults.set(cacheVersion, forKey: CacheKeys.version)
        defaults.set(cachedTotal.totalWords, forKey: CacheKeys.totalWords)
        defaults.set(cachedTotal.totalDuration, forKey: CacheKeys.totalDuration)
        defaults.set(cachedTotal.sessionCount, forKey: CacheKeys.sessionCount)
    }

    private func persistTodayCache() {
        guard let defaults = cacheDefaults else { return }
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
        if storeInMemory {
            rebuildCachesFromSessions(inMemorySessions, currentDate: Date())
            return
        }

        guard let context = modelContext else {
            cachedTotal = .empty
            cachedToday = .empty
            cachedTodayDate = calendar.startOfDay(for: Date())
            persistTotalCache()
            persistTodayCache()
            return
        }

        do {
            let descriptor = FetchDescriptor<TranscriptionSession>()
            let sessions = try context.fetch(descriptor)
            let snapshots = sessions.map { session in
                InMemorySession(
                    startTime: session.startTime,
                    endTime: session.endTime,
                    wordCount: session.wordCount,
                    duration: session.duration,
                    transcribedText: session.transcribedText,
                    language: session.language
                )
            }
            rebuildCachesFromSessions(snapshots, currentDate: Date())
        } catch {
            Log.stats.error("Failed to rebuild stats cache: \(error)")
        }
    }

    private func rebuildCachesFromSessions(_ sessions: [InMemorySession], currentDate: Date) {
        let startOfDay = calendar.startOfDay(for: currentDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        let totalWords = sessions.reduce(0) { $0 + $1.wordCount }
        let totalDuration = sessions.reduce(0.0) { $0 + $1.duration }
        let todaySessions = sessions.filter { session in
            session.startTime >= startOfDay && session.startTime < endOfDay
        }

        cachedTotal = AggregatedStats(
            totalWords: totalWords,
            totalDuration: totalDuration,
            sessionCount: sessions.count
        )
        cachedToday = AggregatedStats(
            totalWords: todaySessions.reduce(0) { $0 + $1.wordCount },
            totalDuration: todaySessions.reduce(0.0) { $0 + $1.duration },
            sessionCount: todaySessions.count
        )
        cachedTodayDate = startOfDay
        persistTotalCache()
        persistTodayCache()
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
        if storeInMemory {
            let session = InMemorySession(
                startTime: now.addingTimeInterval(-duration),
                endTime: now,
                wordCount: wordCount,
                duration: duration,
                transcribedText: text,
                language: language
            )
            inMemorySessions.append(session)
            updateCachesForRecordedSession(wordCount: wordCount, duration: duration, now: now)
            return
        }

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
            updateCachesForRecordedSession(wordCount: wordCount, duration: duration, now: now)
        } catch {
            Log.stats.error("Failed to save session: \(error)")
        }
    }

    private func updateCachesForRecordedSession(wordCount: Int, duration: TimeInterval, now: Date) {
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
        if storeInMemory {
            let sessions = inMemorySessions.filter { session in
                session.startTime >= startDate && session.startTime <= endDate
            }
            return AggregatedStats(
                totalWords: sessions.reduce(0) { $0 + $1.wordCount },
                totalDuration: sessions.reduce(0.0) { $0 + $1.duration },
                sessionCount: sessions.count
            )
        }

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
        if storeInMemory {
            return Array(
                inMemorySessions
                    .sorted { $0.startTime > $1.startTime }
                    .prefix(limit)
                    .map { session in
                        TranscriptionSession(
                            startTime: session.startTime,
                            endTime: session.endTime,
                            wordCount: session.wordCount,
                            duration: session.duration,
                            transcribedText: session.transcribedText,
                            language: session.language
                        )
                    }
            )
        }

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
        if storeInMemory {
            inMemorySessions.removeAll()
            cachedTotal = .empty
            resetTodayCache(for: Date())
            persistTotalCache()
            return
        }

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
