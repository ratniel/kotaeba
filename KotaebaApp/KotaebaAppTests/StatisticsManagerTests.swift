import XCTest
@testable import KotaebaApp

@MainActor
final class StatisticsManagerTests: XCTestCase {
    private var manager: StatisticsManager!

    override func setUp() {
        super.setUp()
        manager = StatisticsManager.shared
        _ = manager.clearAllData()
    }

    override func tearDown() {
        _ = manager.clearAllData()
        manager = nil
        super.tearDown()
    }

    func testTodayCacheUpdatesOnRecordSession() {
        let now = Date()

        _ = manager.getTodayStats(currentDate: now)
        manager.recordSession(wordCount: 5, duration: 10, now: now)

        let updated = manager.getTodayStats(currentDate: now)
        XCTAssertEqual(updated.totalWords, 5)
        XCTAssertEqual(updated.sessionCount, 1)
    }

    func testAggregatedStatsAccumulateAcrossSessions() {
        let now = Date()

        manager.recordSession(wordCount: 3, duration: 5, now: now)
        manager.recordSession(wordCount: 7, duration: 15, now: now.addingTimeInterval(60))

        let stats = manager.getAggregatedStats()
        XCTAssertEqual(stats, AggregatedStats(totalWords: 10, totalDuration: 20, sessionCount: 2))
    }

    func testTodayCacheResetsOnDateChange() {
        let now = Date()

        manager.recordSession(wordCount: 3, duration: 5, now: now)
        _ = manager.getTodayStats(currentDate: now)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let tomorrowStats = manager.getTodayStats(currentDate: tomorrow)

        XCTAssertEqual(tomorrowStats.totalWords, 0)
        XCTAssertEqual(tomorrowStats.sessionCount, 0)
    }

    func testClearAllDataRemovesCachedStats() {
        let now = Date()

        manager.recordSession(wordCount: 4, duration: 6, now: now)
        XCTAssertEqual(manager.getAggregatedStats().sessionCount, 1)

        manager.clearAllData()

        XCTAssertEqual(manager.getAggregatedStats(), .empty)
        XCTAssertEqual(manager.getTodayStats(currentDate: now), .empty)
    }

    func testRecordSessionPersistsHistoryMetadata() {
        let now = Date()

        manager.recordSession(
            wordCount: 2,
            duration: 4,
            text: "hello world",
            language: "en",
            modelIdentifier: "mlx-community/parakeet-tdt-0.6b-v2",
            insertionMethod: TextInsertionMethod.accessibility.rawValue,
            insertionError: nil,
            sourceAppName: "Notes",
            now: now
        )

        let session = manager.getRecentSessions(limit: 1).first
        XCTAssertEqual(session?.transcribedText, "hello world")
        XCTAssertEqual(session?.modelIdentifier, "mlx-community/parakeet-tdt-0.6b-v2")
        XCTAssertEqual(session?.insertionMethod, TextInsertionMethod.accessibility.rawValue)
        XCTAssertNil(session?.insertionError)
        XCTAssertEqual(session?.sourceAppName, "Notes")
    }

    func testRecordSessionPersistsInsertionErrorSeparatelyFromTranscript() {
        let now = Date()

        manager.recordSession(
            wordCount: 2,
            duration: 4,
            text: "hello world",
            language: "en",
            modelIdentifier: "model-id",
            insertionMethod: nil,
            insertionError: TextInsertionError.accessibilityPermissionDenied.localizedDescription,
            sourceAppName: "Terminal",
            now: now
        )

        let session = manager.getRecentSessions(limit: 1).first
        XCTAssertEqual(session?.transcribedText, "hello world")
        XCTAssertNil(session?.insertionMethod)
        XCTAssertEqual(session?.insertionError, TextInsertionError.accessibilityPermissionDenied.localizedDescription)
    }
}
