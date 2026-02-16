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

    static var documentsImportsRoot: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("TTSEvalImports", isDirectory: true)
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

    /// Import bundles pushed into `Documents/TTSEvalImports/<modelId>/...` (e.g., via `devicectl device copy to`).
    ///
    /// This allows host scripts to push large local bundles (like NeMo ONNX weights) into the app container without
    /// enabling file sharing or redistributing weights.
    ///
    /// Returns imported model IDs.
    static func importPendingBundlesFromDocuments() throws -> [String] {
        let root = documentsImportsRoot
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        let modelDirs = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        var imported: [String] = []
        imported.reserveCapacity(modelDirs.count)

        for importDir in modelDirs {
            let modelId = importDir.lastPathComponent
            guard !modelId.isEmpty else { continue }

            let destDir = try modelDirectory(modelId: modelId)
            let items = try fileManager.contentsOfDirectory(at: importDir, includingPropertiesForKeys: nil, options: [])

            for src in items {
                let dst = destDir.appendingPathComponent(src.lastPathComponent, isDirectory: false)
                if fileManager.fileExists(atPath: dst.path) {
                    try? fileManager.removeItem(at: dst)
                }
                do {
                    try fileManager.moveItem(at: src, to: dst)
                } catch {
                    // Cross-volume moves can fail; fall back to copy+delete.
                    try fileManager.copyItem(at: src, to: dst)
                    try? fileManager.removeItem(at: src)
                }
            }

            // Best-effort cleanup.
            try? fileManager.removeItem(at: importDir)
            imported.append(modelId)
        }

        // Remove the root if it's now empty.
        if (try? fileManager.contentsOfDirectory(atPath: root.path).isEmpty) == true {
            try? fileManager.removeItem(at: root)
        }

        return imported
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
