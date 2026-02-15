import Foundation

@MainActor
final class HuggingFaceDownloader: NSObject, @unchecked Sendable {
    private(set) var progress: Double = 0.0
    var onProgress: ((Double) -> Void)?

    private var downloadTask: URLSessionDownloadTask?
    nonisolated(unsafe) private var session: URLSession?
    nonisolated(unsafe) private var continuation: CheckedContinuation<URL, Error>?
    private let continuationLock = NSLock()

    private let progressLock = NSLock()
    nonisolated(unsafe) private var _currentFileIndex: Int = 0
    nonisolated(unsafe) private var _totalFilesToDownload: Int = 1

    private nonisolated var currentFileIndex: Int {
        get { progressLock.withLock { _currentFileIndex } }
        set { progressLock.withLock { _currentFileIndex = newValue } }
    }
    private nonisolated var totalFilesToDownload: Int {
        get { progressLock.withLock { _totalFilesToDownload } }
        set { progressLock.withLock { _totalFilesToDownload = newValue } }
    }

    private static let downloadSessionConfiguration: URLSessionConfiguration = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 45 * 60
        config.waitsForConnectivity = true
        return config
    }()

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        resumeContinuation(with: .failure(CancellationError()))
        session?.invalidateAndCancel()
        session = nil
    }

    func downloadArtifacts(
        modelId: String,
        artifacts: [TTSArtifact]
    ) async throws {
        try Task.checkCancellation()

        guard !artifacts.isEmpty else {
            progress = 1
            onProgress?(1)
            return
        }

        let modelDir = try ModelStorage.modelDirectory(modelId: modelId)
        let fm = FileManager.default
        progress = 0

        // Expand directory artifacts (e.g. "espeak-ng-data/") by listing repo files.
        // We keep v1 UX simple by encoding directories as artifacts whose `path` ends with "/".
        var repoFileCache: [String: [String]] = [:]
        var expanded: [TTSArtifact] = []
        expanded.reserveCapacity(artifacts.count)

        for artifact in artifacts {
            try Task.checkCancellation()

            let srcPrefix = artifact.path
            let dstPrefix = artifact.destinationRelativePath
            let isDirectory = srcPrefix.hasSuffix("/") || dstPrefix.hasSuffix("/")

            if !isDirectory {
                expanded.append(artifact)
                continue
            }

            let normalizedSrc = srcPrefix.hasSuffix("/") ? srcPrefix : (srcPrefix + "/")
            let normalizedDst = dstPrefix.hasSuffix("/") ? dstPrefix : (dstPrefix + "/")

            let files: [String]
            if let cached = repoFileCache[artifact.repoId] {
                files = cached
            } else {
                let listed = try await HuggingFaceAPI.listRepoFiles(repoId: artifact.repoId)
                repoFileCache[artifact.repoId] = listed
                files = listed
            }

            let matches = files.filter { $0.hasPrefix(normalizedSrc) }
            for file in matches {
                try Task.checkCancellation()

                // Defensive: skip directory-like entries if any show up.
                guard !file.hasSuffix("/") else { continue }
                let suffix = String(file.dropFirst(normalizedSrc.count))
                expanded.append(TTSArtifact(repoId: artifact.repoId, path: file, destinationRelativePath: normalizedDst + suffix))
            }
        }

        // Filter out already-present files
        let pending: [TTSArtifact] = expanded.filter { artifact in
            let dest = modelDir.appendingPathComponent(artifact.destinationRelativePath)
            return !fm.fileExists(atPath: dest.path)
        }

        guard !pending.isEmpty else {
            progress = 1
            onProgress?(1)
            return
        }

        totalFilesToDownload = pending.count

        for (idx, artifact) in pending.enumerated() {
            try Task.checkCancellation()

            currentFileIndex = idx

            guard let url = URL(string: "https://huggingface.co/\(artifact.repoId)/resolve/main/\(artifact.path)") else {
                throw TTSEvalError.downloadFailed("Invalid Hugging Face URL for \(artifact.repoId)/\(artifact.path)")
            }

            let tmp = try await downloadFile(from: url)

            let dest = modelDir.appendingPathComponent(artifact.destinationRelativePath)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: tmp, to: dest)
        }

        progress = 1
        onProgress?(1)
    }

    private func downloadFile(from url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let session = URLSession(
                    configuration: Self.downloadSessionConfiguration,
                    delegate: self,
                    delegateQueue: nil
                )
                self.session = session

                continuationLock.lock()
                self.continuation = continuation
                continuationLock.unlock()

                self.downloadTask = session.downloadTask(with: url)
                self.downloadTask?.resume()
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancel()
            }
        }
    }

    private nonisolated func resumeContinuation(with result: Result<URL, Error>) {
        continuationLock.lock()
        let cont = continuation
        continuation = nil
        continuationLock.unlock()

        switch result {
        case .success(let url):
            cont?.resume(returning: url)
        case .failure(let error):
            cont?.resume(throwing: error)
        }
    }

    deinit {
        session?.invalidateAndCancel()
    }
}

extension HuggingFaceDownloader: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory
        let tmpFile = tmpDir.appendingPathComponent(UUID().uuidString)

        do {
            try fm.copyItem(at: location, to: tmpFile)
            session.finishTasksAndInvalidate()
            resumeContinuation(with: .success(tmpFile))
        } catch {
            session.finishTasksAndInvalidate()
            resumeContinuation(with: .failure(error))
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fileFraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let total = Double(max(1, totalFilesToDownload))
        let overallFraction = (Double(currentFileIndex) + fileFraction) / total
        Task { @MainActor [weak self] in
            self?.progress = overallFraction
            self?.onProgress?(overallFraction)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            session.finishTasksAndInvalidate()
            resumeContinuation(with: .failure(error))
        }
    }
}

extension NSLock {
    fileprivate func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
