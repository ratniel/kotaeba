import XCTest
@testable import KotaebaApp

@MainActor
final class StatisticsManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StatisticsManager.shared.clearAllData()
    }

    override func tearDown() {
        StatisticsManager.shared.clearAllData()
        super.tearDown()
    }

    func testTodayCacheUpdatesOnRecordSession() {
        let manager = StatisticsManager.shared
        let now = Date()

        _ = manager.getTodayStats(currentDate: now)
        manager.recordSession(wordCount: 5, duration: 10, now: now)

        let updated = manager.getTodayStats(currentDate: now)
        XCTAssertEqual(updated.totalWords, 5)
        XCTAssertEqual(updated.sessionCount, 1)
    }

    func testTodayCacheResetsOnDateChange() {
        let manager = StatisticsManager.shared
        let now = Date()

        manager.recordSession(wordCount: 3, duration: 5, now: now)
        _ = manager.getTodayStats(currentDate: now)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let tomorrowStats = manager.getTodayStats(currentDate: tomorrow)

        XCTAssertEqual(tomorrowStats.totalWords, 0)
        XCTAssertEqual(tomorrowStats.sessionCount, 0)
    }
}
