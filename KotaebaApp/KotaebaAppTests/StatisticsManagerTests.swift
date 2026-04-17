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
}
