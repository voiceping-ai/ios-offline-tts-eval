import Foundation

enum HuggingFaceAPI {
    struct ModelInfo: Decodable {
        struct Sibling: Decodable {
            let rfilename: String
        }

        let id: String?
        let usedStorage: Int64?
        let siblings: [Sibling]?
    }

    static func fetchModelInfo(repoId: String) async throws -> ModelInfo {
        guard let url = URL(string: "https://huggingface.co/api/models/\(repoId)") else {
            throw TTSEvalError.downloadFailed("Invalid Hugging Face API URL for \(repoId)")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TTSEvalError.downloadFailed("Hugging Face API error \(http.statusCode) for \(repoId): \(body)")
        }
        return try JSONDecoder().decode(ModelInfo.self, from: data)
    }

    static func listRepoFiles(repoId: String) async throws -> [String] {
        let info = try await fetchModelInfo(repoId: repoId)
        return info.siblings?.map { $0.rfilename } ?? []
    }
}
