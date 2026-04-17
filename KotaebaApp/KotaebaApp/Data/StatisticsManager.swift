import Foundation
import SwiftData

@MainActor
protocol StatisticsManaging: AnyObject {
    var isAvailable: Bool { get }
    var lastError: Error? { get }

    func getSnapshot(currentDate: Date) -> StatisticsSnapshot
    @discardableResult func refreshSnapshot(currentDate: Date) -> StatisticsSnapshot
    @discardableResult func recordSession(
        wordCount: Int,
        duration: TimeInterval,
        text: String?,
        language: String,
        now: Date
    ) -> StatisticsSnapshot
    func getAggregatedStats() -> AggregatedStats
    func getTodayStats(currentDate: Date) -> AggregatedStats
    func getRecentSessions(limit: Int) -> [TranscriptionSession]
    @discardableResult func clearAllData(currentDate: Date) -> StatisticsSnapshot
}

fileprivate struct StatisticsSessionRecord {
    let id: UUID
    let startTime: Date
    let endTime: Date?
    let wordCount: Int
    let duration: TimeInterval
    let transcribedText: String?
    let language: String

    init(
        id: UUID = UUID(),
        startTime: Date,
        endTime: Date?,
        wordCount: Int,
        duration: TimeInterval,
        transcribedText: String?,
        language: String
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.wordCount = wordCount
        self.duration = duration
        self.transcribedText = transcribedText
        self.language = language
    }

    init(session: TranscriptionSession) {
        self.init(
            id: session.id,
            startTime: session.startTime,
            endTime: session.endTime,
            wordCount: session.wordCount,
            duration: session.duration,
            transcribedText: session.transcribedText,
            language: session.language
        )
    }

    var model: TranscriptionSession {
        TranscriptionSession(
            id: id,
            startTime: startTime,
            endTime: endTime,
            wordCount: wordCount,
            duration: duration,
            transcribedText: transcribedText,
            language: language
        )
    }
}

@MainActor
fileprivate protocol StatisticsSessionStore: AnyObject {
    var isAvailable: Bool { get }
    var lastError: Error? { get }

    func hasAnySessions() -> Bool
    func fetchAllSessions() -> [StatisticsSessionRecord]
    func fetchSessions(from startDate: Date, to endDate: Date) -> [StatisticsSessionRecord]
    func fetchRecentSessions(limit: Int) -> [TranscriptionSession]
    @discardableResult func save(_ session: StatisticsSessionRecord) -> Bool
    @discardableResult func clearAllData() -> Bool
}

/// Manages statistics tracking and persistence.
///
/// The app talks to this manager through a small repository-like interface.
/// Persistence details stay behind a storage backend so tests can use a pure
/// in-memory implementation without booting SwiftData.
@MainActor
final class StatisticsManager: StatisticsManaging {
    static let shared = StatisticsManager(storeInMemory: Constants.isRunningTests)

    private let store: any StatisticsSessionStore
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let usePersistentCache: Bool

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

    var isAvailable: Bool { store.isAvailable }
    var lastError: Error? { store.lastError }

    init(storeInMemory: Bool = false, defaults: UserDefaults? = nil, calendar: Calendar = .current) {
        let resolvedStore: any StatisticsSessionStore
        let usePersistentCache = !storeInMemory

        if storeInMemory {
            resolvedStore = InMemoryStatisticsSessionStore()
        } else {
            resolvedStore = SwiftDataStatisticsSessionStore(
                storeURL: Constants.supportDirectory.appendingPathComponent("Statistics.store")
            )
        }

        self.store = resolvedStore
        self.defaults = defaults ?? .standard
        self.calendar = calendar
        self.usePersistentCache = usePersistentCache
        loadCachedStats()
    }

    nonisolated deinit {}

    private func loadCachedStats() {
        guard usePersistentCache else {
            cachedTotal = .empty
            cachedToday = .empty
            cachedTodayDate = nil
            return
        }

        let version = defaults.integer(forKey: CacheKeys.version)
        if version != cacheVersion {
            rebuildCaches(currentDate: Date())
            return
        }

        cachedTotal = AggregatedStats(
            totalWords: defaults.integer(forKey: CacheKeys.totalWords),
            totalDuration: defaults.double(forKey: CacheKeys.totalDuration),
            sessionCount: defaults.integer(forKey: CacheKeys.sessionCount)
        )

        let storedDate = defaults.object(forKey: CacheKeys.todayDate) as? Date
        if let storedDate, calendar.isDateInToday(storedDate) {
            cachedTodayDate = calendar.startOfDay(for: storedDate)
            cachedToday = AggregatedStats(
                totalWords: defaults.integer(forKey: CacheKeys.todayWords),
                totalDuration: defaults.double(forKey: CacheKeys.todayDuration),
                sessionCount: defaults.integer(forKey: CacheKeys.todaySessionCount)
            )
        } else {
            resetTodayCache(for: Date())
        }

        if cachedTotal.sessionCount == 0, store.hasAnySessions() {
            rebuildCaches(currentDate: Date())
        }
    }

    private func persistTotalCache() {
        guard usePersistentCache else { return }
        defaults.set(cacheVersion, forKey: CacheKeys.version)
        defaults.set(cachedTotal.totalWords, forKey: CacheKeys.totalWords)
        defaults.set(cachedTotal.totalDuration, forKey: CacheKeys.totalDuration)
        defaults.set(cachedTotal.sessionCount, forKey: CacheKeys.sessionCount)
    }

    private func persistTodayCache() {
        guard usePersistentCache else { return }
        defaults.set(cachedTodayDate, forKey: CacheKeys.todayDate)
        defaults.set(cachedToday.totalWords, forKey: CacheKeys.todayWords)
        defaults.set(cachedToday.totalDuration, forKey: CacheKeys.todayDuration)
        defaults.set(cachedToday.sessionCount, forKey: CacheKeys.todaySessionCount)
    }

    private func resetTodayCache(for date: Date) {
        cachedTodayDate = calendar.startOfDay(for: date)
        cachedToday = .empty
        persistTodayCache()
    }

    private func aggregate(_ sessions: [StatisticsSessionRecord]) -> AggregatedStats {
        AggregatedStats(
            totalWords: sessions.reduce(0) { $0 + $1.wordCount },
            totalDuration: sessions.reduce(0.0) { $0 + $1.duration },
            sessionCount: sessions.count
        )
    }

    private func rebuildCaches(currentDate: Date) {
        let sessions = store.fetchAllSessions()
        let startOfDay = calendar.startOfDay(for: currentDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        cachedTotal = aggregate(sessions)
        cachedToday = aggregate(
            sessions.filter { session in
                session.startTime >= startOfDay && session.startTime < endOfDay
            }
        )
        cachedTodayDate = startOfDay
        persistTotalCache()
        persistTodayCache()
    }

    func getSnapshot(currentDate: Date = Date()) -> StatisticsSnapshot {
        if cachedTotal.sessionCount == 0, store.hasAnySessions() {
            rebuildCaches(currentDate: currentDate)
        }

        let today = getTodayStats(currentDate: currentDate)
        return StatisticsSnapshot(total: cachedTotal, today: today)
    }

    @discardableResult
    func refreshSnapshot(currentDate: Date = Date()) -> StatisticsSnapshot {
        rebuildCaches(currentDate: currentDate)
        return StatisticsSnapshot(total: cachedTotal, today: cachedToday)
    }

    @discardableResult
    func recordSession(
        wordCount: Int,
        duration: TimeInterval,
        text: String? = nil,
        language: String = "en",
        now: Date = Date()
    ) -> StatisticsSnapshot {
        let session = StatisticsSessionRecord(
            startTime: now.addingTimeInterval(-duration),
            endTime: now,
            wordCount: wordCount,
            duration: duration,
            transcribedText: text,
            language: language
        )

        guard store.save(session) else {
            return getSnapshot(currentDate: now)
        }

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

        return StatisticsSnapshot(total: cachedTotal, today: cachedToday)
    }

    func getAggregatedStats() -> AggregatedStats {
        getSnapshot(currentDate: Date()).total
    }

    func getTodayStats(currentDate: Date = Date()) -> AggregatedStats {
        let startOfDay = calendar.startOfDay(for: currentDate)
        if cachedTodayDate == startOfDay {
            return cachedToday
        }

        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        cachedToday = aggregate(store.fetchSessions(from: startOfDay, to: endOfDay))
        cachedTodayDate = startOfDay
        persistTodayCache()
        return cachedToday
    }

    func getRecentSessions(limit: Int = 10) -> [TranscriptionSession] {
        store.fetchRecentSessions(limit: limit)
    }

    @discardableResult
    func clearAllData(currentDate: Date = Date()) -> StatisticsSnapshot {
        guard store.clearAllData() else {
            return getSnapshot(currentDate: currentDate)
        }

        cachedTotal = .empty
        resetTodayCache(for: currentDate)
        persistTotalCache()
        return StatisticsSnapshot(total: cachedTotal, today: cachedToday)
    }
}

@MainActor
private final class InMemoryStatisticsSessionStore: StatisticsSessionStore {
    private var sessions: [StatisticsSessionRecord] = []

    let isAvailable = true
    let lastError: Error? = nil

    nonisolated deinit {}

    func hasAnySessions() -> Bool {
        !sessions.isEmpty
    }

    func fetchAllSessions() -> [StatisticsSessionRecord] {
        sessions
    }

    func fetchSessions(from startDate: Date, to endDate: Date) -> [StatisticsSessionRecord] {
        sessions.filter { session in
            session.startTime >= startDate && session.startTime < endDate
        }
    }

    func fetchRecentSessions(limit: Int) -> [TranscriptionSession] {
        sessions
            .sorted { $0.startTime > $1.startTime }
            .prefix(limit)
            .map(\.model)
    }

    @discardableResult
    func save(_ session: StatisticsSessionRecord) -> Bool {
        sessions.append(session)
        return true
    }

    @discardableResult
    func clearAllData() -> Bool {
        sessions.removeAll()
        return true
    }
}

@MainActor
private final class SwiftDataStatisticsSessionStore: StatisticsSessionStore {
    private let modelContainer: ModelContainer?
    private let modelContext: ModelContext?

    private(set) var isAvailable = true
    private(set) var lastError: Error?

    nonisolated deinit {}

    init(storeURL: URL) {
        do {
            let schema = Schema([TranscriptionSession.self])
            let storeDirectory = storeURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)

            let configuration = ModelConfiguration(
                "KotaebaStats",
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            self.modelContainer = container
            self.modelContext = ModelContext(container)
            self.lastError = nil
        } catch {
            Log.stats.error("Failed to setup statistics store: \(error)")
            self.modelContainer = nil
            self.modelContext = nil
            self.isAvailable = false
            self.lastError = error
        }
    }

    func hasAnySessions() -> Bool {
        guard let context = modelContext else { return false }

        do {
            var descriptor = FetchDescriptor<TranscriptionSession>()
            descriptor.fetchLimit = 1
            return try !context.fetch(descriptor).isEmpty
        } catch {
            Log.stats.error("Failed to check sessions: \(error)")
            lastError = error
            return false
        }
    }

    func fetchAllSessions() -> [StatisticsSessionRecord] {
        guard let context = modelContext else { return [] }

        do {
            let descriptor = FetchDescriptor<TranscriptionSession>()
            return try context.fetch(descriptor).map(StatisticsSessionRecord.init(session:))
        } catch {
            Log.stats.error("Failed to fetch sessions: \(error)")
            lastError = error
            return []
        }
    }

    func fetchSessions(from startDate: Date, to endDate: Date) -> [StatisticsSessionRecord] {
        guard let context = modelContext else { return [] }

        do {
            let predicate = #Predicate<TranscriptionSession> { session in
                session.startTime >= startDate && session.startTime < endDate
            }
            let descriptor = FetchDescriptor<TranscriptionSession>(predicate: predicate)
            return try context.fetch(descriptor).map(StatisticsSessionRecord.init(session:))
        } catch {
            Log.stats.error("Failed to fetch sessions for range: \(error)")
            lastError = error
            return []
        }
    }

    func fetchRecentSessions(limit: Int) -> [TranscriptionSession] {
        guard let context = modelContext else { return [] }

        do {
            var descriptor = FetchDescriptor<TranscriptionSession>(
                sortBy: [SortDescriptor(\.startTime, order: .reverse)]
            )
            descriptor.fetchLimit = limit
            return try context.fetch(descriptor)
        } catch {
            Log.stats.error("Failed to fetch recent sessions: \(error)")
            lastError = error
            return []
        }
    }

    @discardableResult
    func save(_ session: StatisticsSessionRecord) -> Bool {
        guard let context = modelContext else {
            Log.stats.error("Model context not available")
            return false
        }

        context.insert(session.model)

        do {
            try context.save()
            lastError = nil
            Log.stats.info("Session recorded: \(session.wordCount) words, \(Int(session.duration))s")
            return true
        } catch {
            Log.stats.error("Failed to save session: \(error)")
            lastError = error
            return false
        }
    }

    @discardableResult
    func clearAllData() -> Bool {
        guard let context = modelContext else { return false }

        do {
            try context.delete(model: TranscriptionSession.self)
            try context.save()
            lastError = nil
            Log.stats.info("All data cleared")
            return true
        } catch {
            Log.stats.error("Failed to clear data: \(error)")
            lastError = error
            return false
        }
    }
}
