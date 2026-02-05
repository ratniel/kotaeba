import XCTest
@testable import KotaebaApp

final class ClientConfigEncodingTests: XCTestCase {
    func testEncodingUsesSnakeCaseKeys() throws {
        let config = ClientConfig.with(model: "test-model")
        let data = try JSONEncoder().encode(config)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(object?["model"] as? String, "test-model")
        XCTAssertEqual(object?["language"] as? String, "en")
        XCTAssertEqual(object?["sample_rate"] as? Int, Int(Constants.Audio.sampleRate))
        XCTAssertEqual(object?["channels"] as? Int, Int(Constants.Audio.channels))
        XCTAssertEqual(object?["vad_enabled"] as? Bool, true)
        XCTAssertEqual(object?["vad_aggressiveness"] as? Int, 3)
    }
}
