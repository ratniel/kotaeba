import XCTest
@testable import KotaebaApp

final class SettingsMigrationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsMigrationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testMigratesLegacyLoopbackPortToCurrentDefault() {
        defaults.set("localhost", forKey: Constants.UserDefaultsKeys.serverHost)
        defaults.set(8000, forKey: Constants.UserDefaultsKeys.serverPort)

        SettingsMigration.migrateIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.integer(forKey: Constants.UserDefaultsKeys.serverPort), Constants.Server.defaultPort)
        XCTAssertEqual(defaults.integer(forKey: Constants.UserDefaultsKeys.serverPortMigrationVersion), SettingsMigration.currentVersion)
    }

    func testDoesNotChangeRemoteHostPort() {
        defaults.set("192.168.1.25", forKey: Constants.UserDefaultsKeys.serverHost)
        defaults.set(8000, forKey: Constants.UserDefaultsKeys.serverPort)

        SettingsMigration.migrateIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.integer(forKey: Constants.UserDefaultsKeys.serverPort), 8000)
        XCTAssertEqual(defaults.integer(forKey: Constants.UserDefaultsKeys.serverPortMigrationVersion), SettingsMigration.currentVersion)
    }

    func testDoesNotOverrideUserPortAfterMigrationRuns() {
        defaults.set("localhost", forKey: Constants.UserDefaultsKeys.serverHost)
        defaults.set(8000, forKey: Constants.UserDefaultsKeys.serverPort)

        SettingsMigration.migrateIfNeeded(defaults: defaults)
        defaults.set(8000, forKey: Constants.UserDefaultsKeys.serverPort)

        SettingsMigration.migrateIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.integer(forKey: Constants.UserDefaultsKeys.serverPort), 8000)
    }
}
