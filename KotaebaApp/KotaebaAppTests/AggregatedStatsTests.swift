import XCTest
@testable import KotaebaApp

final class AggregatedStatsTests: XCTestCase {
    func testEstimatedTimeSaved() {
        let stats = AggregatedStats(totalWords: 100, totalDuration: 0, sessionCount: 1)
        XCTAssertEqual(stats.estimatedTimeSaved, 110.0, accuracy: 0.0001)
    }

    func testFormattedDurationHours() {
        let stats = AggregatedStats(totalWords: 0, totalDuration: 3661, sessionCount: 1)
        XCTAssertEqual(stats.formattedDuration, "1h 1m")
    }

    func testFormattedDurationSeconds() {
        let stats = AggregatedStats(totalWords: 0, totalDuration: 59, sessionCount: 1)
        XCTAssertEqual(stats.formattedDuration, "59s")
    }
}
