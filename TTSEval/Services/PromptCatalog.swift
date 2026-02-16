import Foundation

struct PromptSets: Decodable, Sendable {
    let short: [String]
    let medium: [String]
    let long: [String]
}

enum PromptLanguage: String, CaseIterable, Identifiable {
    case en
    case zh
    case ja
    case ko

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "EN"
        case .zh: return "ZH"
        case .ja: return "JA"
        case .ko: return "KO"
        }
    }
}

enum PromptDataset: String, CaseIterable, Identifiable {
    case short
    case medium
    case long
    case all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .short: return "Short"
        case .medium: return "Medium"
        case .long: return "Long"
        case .all: return "All"
        }
    }
}

enum PromptCatalog {
    typealias LanguageMap = [String: PromptSets]

    static func load() throws -> LanguageMap {
        guard let url = Bundle.main.url(forResource: "prompts", withExtension: "json") else {
            throw TTSEvalError.invalidModel("prompts.json not found in bundle")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LanguageMap.self, from: data)
    }

    static func prompts(for language: PromptLanguage, dataset: PromptDataset, setsByLanguage: LanguageMap) throws -> [String] {
        guard let sets = setsByLanguage[language.rawValue] else {
            throw TTSEvalError.invalidModel("No prompts found for language: \(language.rawValue)")
        }
        return prompts(for: dataset, sets: sets)
    }

    private static func prompts(for dataset: PromptDataset, sets: PromptSets) -> [String] {
        switch dataset {
        case .short: return sets.short
        case .medium: return sets.medium
        case .long: return sets.long
        case .all: return sets.short + sets.medium + sets.long
        }
    }
}
