import XCTest
@testable import KotaebaApp

final class ModelCatalogTests: XCTestCase {
    func testDecodesBundledProjectCatalog() throws {
        let catalog = try ModelCatalogLoader.decode(projectCatalogData())

        XCTAssertEqual(catalog.defaultModel.identifier, "mlx-community/parakeet-tdt-0.6b-v2")
        XCTAssertEqual(catalog.models.count, 2)
        XCTAssertEqual(catalog.models[0].languageCoverage, "English")
        XCTAssertEqual(catalog.models[0].speedLabel, "Fast")
        XCTAssertEqual(catalog.models[1].qualityLabel, "High quality")
    }

    func testMissingCatalogUsesFallback() {
        let catalog = ModelCatalogLoader.load(resourceURL: nil)

        XCTAssertEqual(catalog, ModelCatalogLoader.fallbackCatalog)
    }

    func testMalformedCatalogUsesFallback() {
        let url = temporaryCatalogURL(contents: "{")
        defer { try? FileManager.default.removeItem(at: url) }

        let catalog = ModelCatalogLoader.load(resourceURL: url)

        XCTAssertEqual(catalog, ModelCatalogLoader.fallbackCatalog)
    }

    func testRejectsDuplicateIdentifiers() {
        let data = Data("""
        {
          "default_model": "mlx-community/parakeet-tdt-0.6b-v2",
          "models": [
            {
              "name": "Parakeet",
              "identifier": "mlx-community/parakeet-tdt-0.6b-v2",
              "description": "Fast",
              "language_coverage": "English",
              "size": "0.6B",
              "speed_label": "Fast",
              "quality_label": "Balanced"
            },
            {
              "name": "Duplicate",
              "identifier": "mlx-community/parakeet-tdt-0.6b-v2",
              "description": "Duplicate",
              "language_coverage": "English",
              "size": "0.6B",
              "speed_label": "Fast",
              "quality_label": "Balanced"
            }
          ]
        }
        """.utf8)

        XCTAssertThrowsError(try ModelCatalogLoader.decode(data)) { error in
            XCTAssertEqual(error as? ModelCatalogError, .duplicateIdentifiers(["mlx-community/parakeet-tdt-0.6b-v2"]))
        }
    }

    func testRejectsMissingDefaultModel() {
        let data = Data("""
        {
          "default_model": "mlx-community/missing",
          "models": [
            {
              "name": "Parakeet",
              "identifier": "mlx-community/parakeet-tdt-0.6b-v2",
              "description": "Fast",
              "language_coverage": "English",
              "size": "0.6B",
              "speed_label": "Fast",
              "quality_label": "Balanced"
            }
          ]
        }
        """.utf8)

        XCTAssertThrowsError(try ModelCatalogLoader.decode(data)) { error in
            XCTAssertEqual(error as? ModelCatalogError, .missingDefaultModel("mlx-community/missing"))
        }
    }

    func testRejectsEmptyMetadata() {
        let data = Data("""
        {
          "default_model": "mlx-community/parakeet-tdt-0.6b-v2",
          "models": [
            {
              "name": " ",
              "identifier": "mlx-community/parakeet-tdt-0.6b-v2",
              "description": "Fast",
              "language_coverage": "English",
              "size": "0.6B",
              "speed_label": "Fast",
              "quality_label": "Balanced"
            }
          ]
        }
        """.utf8)

        XCTAssertThrowsError(try ModelCatalogLoader.decode(data)) { error in
            XCTAssertEqual(error as? ModelCatalogError, .malformedMetadata("name"))
        }
    }

    func testRejectsUnsafeModelIdentifier() {
        let data = Data("""
        {
          "default_model": "mlx-community/parakeet-tdt-0.6b-v2",
          "models": [
            {
              "name": "Unsafe",
              "identifier": "mlx-community/parakeet'); import os; os.system('whoami') #",
              "description": "Unsafe",
              "language_coverage": "English",
              "size": "0.6B",
              "speed_label": "Fast",
              "quality_label": "Balanced"
            }
          ]
        }
        """.utf8)

        XCTAssertThrowsError(try ModelCatalogLoader.decode(data)) { error in
            XCTAssertEqual(
                error as? ModelCatalogError,
                .invalidIdentifier("mlx-community/parakeet'); import os; os.system('whoami') #")
            )
        }
    }

    func testCustomModelStorePersistsValidatedModels() {
        let suiteName = "ModelCatalogTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = Constants.Models.Model(
            name: "Custom",
            identifier: "mlx-community/custom-stt-model",
            description: "Custom Hugging Face model",
            languageCoverage: "EN",
            size: "Custom",
            speedLabel: "Custom",
            qualityLabel: "Validated"
        )

        CustomModelCatalogStore.upsert(model, defaults: defaults)

        XCTAssertEqual(CustomModelCatalogStore.loadModels(defaults: defaults), [model])
    }

    func testCustomModelMetadataUsesHuggingFaceInfo() {
        let model = CustomModelCatalogStore.model(
            for: HuggingFaceModelInfo(
                id: "mlx-community/custom-stt-model",
                pipelineTag: "automatic-speech-recognition",
                tags: ["language:en", "mlx"]
            )
        )

        XCTAssertEqual(model.name, "custom-stt-model")
        XCTAssertEqual(model.identifier, "mlx-community/custom-stt-model")
        XCTAssertEqual(model.languageCoverage, "EN")
        XCTAssertEqual(model.qualityLabel, "Validated")
    }

    func testSpeechToTextValidationAllowsRelevantTagsWithoutPipelineTag() throws {
        XCTAssertNoThrow(
            try HuggingFaceModelLookup.validateSpeechToTextCandidate(
                HuggingFaceModelInfo(
                    id: "mlx-community/custom-stt-model",
                    pipelineTag: nil,
                    tags: ["speech-to-text", "mlx"]
                )
            )
        )
    }

    func testSpeechToTextValidationRejectsMissingPipelineTagWithoutSpeechTags() {
        XCTAssertThrowsError(
            try HuggingFaceModelLookup.validateSpeechToTextCandidate(
                HuggingFaceModelInfo(
                    id: "mlx-community/not-asr-model",
                    pipelineTag: nil,
                    tags: ["mlx", "audio"]
                )
            )
        ) { error in
            XCTAssertEqual(error as? HuggingFaceModelLookupError, .notSpeechToTextModel("mlx-community/not-asr-model"))
        }
    }

    private func projectCatalogData() throws -> Data {
        let testFile = URL(fileURLWithPath: #filePath)
        let catalogURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("KotaebaApp/Resources/ModelCatalog.json")
        return try Data(contentsOf: catalogURL)
    }

    private func temporaryCatalogURL(contents: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelCatalogTests-\(UUID().uuidString).json")
        FileManager.default.createFile(atPath: url.path, contents: Data(contents.utf8))
        return url
    }

}
