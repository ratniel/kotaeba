import Foundation

struct ModelCatalog: Equatable {
    let defaultModelIdentifier: String
    let models: [Constants.Models.Model]

    var defaultModel: Constants.Models.Model {
        models.first { $0.identifier == defaultModelIdentifier } ?? ModelCatalogLoader.fallbackModels[0]
    }

    func model(withIdentifier identifier: String) -> Constants.Models.Model? {
        let normalizedIdentifier = Constants.Models.normalizedIdentifier(identifier)
        return models.first { $0.identifier == normalizedIdentifier }
    }
}

struct HuggingFaceModelInfo: Decodable, Equatable {
    let id: String
    let pipelineTag: String?
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case pipelineTag = "pipeline_tag"
        case tags
    }

    init(id: String, pipelineTag: String? = nil, tags: [String] = []) {
        self.id = id
        self.pipelineTag = pipelineTag
        self.tags = tags
    }
}

enum ModelCatalogError: Error, Equatable, LocalizedError {
    case emptyCatalog
    case malformedMetadata(String)
    case duplicateIdentifiers([String])
    case missingDefaultModel(String)
    case invalidIdentifier(String)

    var errorDescription: String? {
        switch self {
        case .emptyCatalog:
            return "Model catalog must include at least one model."
        case .malformedMetadata(let field):
            return "Model catalog contains malformed metadata for \(field)."
        case .duplicateIdentifiers(let identifiers):
            return "Model catalog contains duplicate identifiers: \(identifiers.joined(separator: ", "))."
        case .missingDefaultModel(let identifier):
            return "Model catalog default model is missing: \(identifier)."
        case .invalidIdentifier(let identifier):
            return "Model catalog contains an invalid model identifier: \(identifier)."
        }
    }
}

enum ModelCatalogLoader {
    static let resourceName = "ModelCatalog"
    static let resourceExtension = "json"

    static let fallbackModels: [Constants.Models.Model] = [
        Constants.Models.Model(
            name: "Parakeet-TDT-0.6B",
            identifier: "mlx-community/parakeet-tdt-0.6b-v2",
            description: "Fast, low memory",
            languageCoverage: "English",
            size: "0.6B",
            speedLabel: "Fast",
            qualityLabel: "Balanced"
        ),
        Constants.Models.Model(
            name: "Whisper Large V3 Turbo",
            identifier: "mlx-community/whisper-large-v3-turbo",
            description: "High quality, balanced",
            languageCoverage: "Multilingual",
            size: "Large V3 Turbo",
            speedLabel: "Balanced",
            qualityLabel: "High quality"
        )
    ]

    static let fallbackCatalog = ModelCatalog(
        defaultModelIdentifier: fallbackModels[0].identifier,
        models: fallbackModels
    )

    static func load(bundle: Bundle = .main) -> ModelCatalog {
        load(resourceURL: bundle.url(forResource: resourceName, withExtension: resourceExtension))
    }

    static func load(resourceURL: URL?) -> ModelCatalog {
        guard let resourceURL else {
            Log.app.warning("Model catalog resource is missing; using fallback catalog.")
            return fallbackCatalog
        }

        do {
            let data = try Data(contentsOf: resourceURL)
            return try decode(data)
        } catch {
            Log.app.error("Model catalog could not be loaded: \(error.localizedDescription). Using fallback catalog.")
            return fallbackCatalog
        }
    }

    static func decode(_ data: Data) throws -> ModelCatalog {
        let resource = try JSONDecoder().decode(ModelCatalogResource.self, from: data)
        return try validate(resource)
    }

    private static func validate(_ resource: ModelCatalogResource) throws -> ModelCatalog {
        let defaultModelIdentifier = resource.defaultModelIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !defaultModelIdentifier.isEmpty else {
            throw ModelCatalogError.malformedMetadata("default_model")
        }
        guard isValidModelIdentifier(defaultModelIdentifier) else {
            throw ModelCatalogError.invalidIdentifier(defaultModelIdentifier)
        }

        guard !resource.models.isEmpty else {
            throw ModelCatalogError.emptyCatalog
        }

        var seenIdentifiers = Set<String>()
        var duplicateIdentifiers = Set<String>()
        let models = try resource.models.map { model -> Constants.Models.Model in
            let normalizedModel = Constants.Models.Model(
                name: try nonEmpty(model.name, field: "name"),
                identifier: try nonEmpty(model.identifier, field: "identifier"),
                description: try nonEmpty(model.description, field: "description"),
                languageCoverage: try nonEmpty(model.languageCoverage, field: "language_coverage"),
                size: try nonEmpty(model.size, field: "size"),
                speedLabel: try nonEmpty(model.speedLabel, field: "speed_label"),
                qualityLabel: try nonEmpty(model.qualityLabel, field: "quality_label")
            )
            guard isValidModelIdentifier(normalizedModel.identifier) else {
                throw ModelCatalogError.invalidIdentifier(normalizedModel.identifier)
            }

            if !seenIdentifiers.insert(normalizedModel.identifier).inserted {
                duplicateIdentifiers.insert(normalizedModel.identifier)
            }

            return normalizedModel
        }

        if !duplicateIdentifiers.isEmpty {
            throw ModelCatalogError.duplicateIdentifiers(duplicateIdentifiers.sorted())
        }

        guard models.contains(where: { $0.identifier == defaultModelIdentifier }) else {
            throw ModelCatalogError.missingDefaultModel(defaultModelIdentifier)
        }

        return ModelCatalog(
            defaultModelIdentifier: defaultModelIdentifier,
            models: models
        )
    }

    private static func nonEmpty(_ value: String, field: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ModelCatalogError.malformedMetadata(field)
        }
        return trimmed
    }

    static func isValidModelIdentifier(_ identifier: String) -> Bool {
        let pattern = #"^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$"#
        return identifier.range(of: pattern, options: .regularExpression) != nil
    }
}

enum CustomModelCatalogStore {
    static func loadModels(defaults: UserDefaults = .standard) -> [Constants.Models.Model] {
        guard let data = defaults.data(forKey: Constants.UserDefaultsKeys.customModels) else {
            return []
        }

        do {
            let decodedModels = try JSONDecoder().decode([Constants.Models.Model].self, from: data)
            return decodedModels.filter { ModelCatalogLoader.isValidModelIdentifier($0.identifier) }
        } catch {
            Log.app.error("Custom model catalog could not be loaded: \(error.localizedDescription)")
            return []
        }
    }

    static func upsert(_ model: Constants.Models.Model, defaults: UserDefaults = .standard) {
        var models = loadModels(defaults: defaults)
        if let existingIndex = models.firstIndex(where: { $0.identifier == model.identifier }) {
            models[existingIndex] = model
        } else {
            models.append(model)
        }
        save(models, defaults: defaults)
    }

    static func save(_ models: [Constants.Models.Model], defaults: UserDefaults = .standard) {
        let validModels = Constants.Models.mergedModels(bundledModels: [], customModels: models)
            .filter { ModelCatalogLoader.isValidModelIdentifier($0.identifier) }
        do {
            let data = try JSONEncoder().encode(validModels)
            defaults.set(data, forKey: Constants.UserDefaultsKeys.customModels)
        } catch {
            Log.app.error("Custom model catalog could not be saved: \(error.localizedDescription)")
        }
    }

    static func model(for info: HuggingFaceModelInfo) -> Constants.Models.Model {
        let identifier = Constants.Models.normalizedIdentifier(info.id)
        let repoName = identifier.split(separator: "/").last.map(String.init) ?? identifier
        let languageCoverage = languageCoverage(from: info.tags)

        return Constants.Models.Model(
            name: repoName,
            identifier: identifier,
            description: "Custom Hugging Face model",
            languageCoverage: languageCoverage,
            size: "Custom",
            speedLabel: "Custom",
            qualityLabel: "Validated"
        )
    }

    private static func languageCoverage(from tags: [String]) -> String {
        let languageTags = tags.compactMap { tag -> String? in
            guard tag.hasPrefix("language:") else { return nil }
            return String(tag.dropFirst("language:".count)).uppercased()
        }
        return languageTags.isEmpty ? "Custom" : languageTags.joined(separator: ", ")
    }
}

private struct ModelCatalogResource: Decodable {
    let defaultModelIdentifier: String
    let models: [Constants.Models.Model]

    enum CodingKeys: String, CodingKey {
        case defaultModelIdentifier = "default_model"
        case models
    }
}
