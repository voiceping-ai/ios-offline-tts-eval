import Foundation

enum ModelStorage {
    private static let fileManager = FileManager.default

    static var appSupportRoot: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("VoicePingTTSEval", isDirectory: true)
    }

    static var modelsRoot: URL {
        appSupportRoot.appendingPathComponent("Models", isDirectory: true)
    }

    static var customModelsFile: URL {
        appSupportRoot.appendingPathComponent("custom_models.json", isDirectory: false)
    }

    static func ensureDirectories() throws {
        try fileManager.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
    }

    static func modelDirectory(modelId: String) throws -> URL {
        try ensureDirectories()
        let dir = modelsRoot.appendingPathComponent(modelId, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func isModelDownloaded(_ model: TTSModel) -> Bool {
        do {
            let dir = try modelDirectory(modelId: model.id)
            if !model.artifacts.isEmpty {
                return model.artifacts.allSatisfy { artifact in
                    let path = dir.appendingPathComponent(artifact.destinationRelativePath)
                    return fileManager.fileExists(atPath: path.path)
                }
            }

            if !model.localRequiredPaths.isEmpty {
                return model.localRequiredPaths.allSatisfy { rel in
                    let trimmed = rel.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return true }
                    let path = dir.appendingPathComponent(trimmed, isDirectory: false)
                    return fileManager.fileExists(atPath: path.path)
                }
            }

            // System/baseline models with no download/import requirements.
            return true
        } catch {
            return false
        }
    }

    static func localArtifactURL(modelId: String, artifact: TTSArtifact) throws -> URL {
        let dir = try modelDirectory(modelId: modelId)
        return dir.appendingPathComponent(artifact.destinationRelativePath)
    }

    static func deleteDownloadedModel(modelId: String) throws {
        let dir = modelsRoot.appendingPathComponent(modelId, isDirectory: true)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
    }

    static func downloadedSizeBytes(modelId: String) -> Int64 {
        let dir = modelsRoot.appendingPathComponent(modelId, isDirectory: true)
        guard fileManager.fileExists(atPath: dir.path) else { return 0 }

        var total: Int64 = 0
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: Array(keys))
        while let url = enumerator?.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    static func loadCustomModels() -> [TTSModel] {
        do {
            let data = try Data(contentsOf: customModelsFile)
            return try JSONDecoder().decode([TTSModel].self, from: data)
        } catch {
            return []
        }
    }

    static func saveCustomModels(_ models: [TTSModel]) throws {
        try ensureDirectories()
        let data = try JSONEncoder().encode(models)
        try data.write(to: customModelsFile, options: [.atomic])
    }
}
