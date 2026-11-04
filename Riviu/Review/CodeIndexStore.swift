import Foundation
import Observation
import RiviuGitHub
import RiviuSupport
import RiviuSyntax

/// Indexes of whole repositories at one commit, for the hot path and Go to Definition.
///
/// The commit is downloaded once as a tarball, unpacked into Caches, and every source file is parsed
/// with its grammar's tags query. Nothing is cloned and no language server is needed.
@Observable
final class CodeIndexStore {
    enum State {
        case building(String)
        case ready(SymbolIndex)
        case failed(String)
    }

    private(set) var states: [String: State] = [:]

    /// Repositories bigger than this are indexed from the pull request's own files instead.
    private static let maxRepositoryKilobytes = 300_000
    private static let maxFiles = 6_000
    private static let maxFileBytes = 512_000
    private static let skippedFolders: Set<String> = ["node_modules", "vendor", "Pods", ".build", "build", "dist", "third_party",
                                                     ".git", "DerivedData", "target", "__pycache__"]

    @ObservationIgnored private let account: GitHubAccount
    @ObservationIgnored private let cacheURL = URL.cachesDirectory.appending(path: "Riviu/Snapshots", directoryHint: .isDirectory)

    init(account: GitHubAccount) {
        self.account = account
    }

    func state(for pullRequest: PullRequest) -> State? {
        states[key(for: pullRequest)]
    }

    func index(for pullRequest: PullRequest) -> SymbolIndex? {
        if case let .ready(index) = state(for: pullRequest) { return index }
        return nil
    }

    /// Starts indexing unless it's done or under way. `files` are used when the repository can't be downloaded.
    func prepare(_ pullRequest: PullRequest, fallbackFiles: @escaping () async -> [(path: String, text: String)]) {
        let key = key(for: pullRequest)
        switch states[key] {
        case .building, .ready: return
        case .failed, nil: break
        }
        states[key] = .building("Downloading the repository…")
        Task {
            do {
                let files = try await sourceFiles(for: pullRequest, fallbackFiles: fallbackFiles)
                states[key] = .building("Indexing \(files.count) files…")
                states[key] = .ready(await SymbolIndex.build(files: files))
            } catch {
                states[key] = .failed(error.localizedDescription)
            }
        }
    }

    private func key(for pullRequest: PullRequest) -> String {
        "\(pullRequest.reference.repository)@\(pullRequest.headSHA)"
    }

    // MARK: - Getting the files

    private func sourceFiles(for pullRequest: PullRequest,
                             fallbackFiles: () async -> [(path: String, text: String)]) async throws -> [(path: String, text: String)] {
        let repository = pullRequest.reference.repository
        guard let client = account.client,
              let size = try? await client.repositorySize(repository), size <= Self.maxRepositoryKilobytes else {
            return await fallbackFiles()
        }
        let folder = cacheURL.appending(path: "\(repository.replacingOccurrences(of: "/", with: "_"))-\(pullRequest.headSHA)",
                                        directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: folder.path) {
            let tarball = try await client.downloadTarball(repository: repository, ref: pullRequest.headSHA)
            try await unpack(tarball, into: folder)
        }
        return try readSourceFiles(in: folder)
    }

    private func unpack(_ tarball: URL, into folder: URL) async throws {
        let partial = folder.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: partial)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        // GitHub wraps everything in one "owner-repo-sha" folder; --strip-components drops it.
        let result = try await ChildProcess.output(of: URL(filePath: "/usr/bin/tar"),
                                                   arguments: ["-xzf", tarball.path, "-C", partial.path, "--strip-components", "1"])
        try? FileManager.default.removeItem(at: tarball)
        guard result.status == 0 else {
            try? FileManager.default.removeItem(at: partial)
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "Couldn't unpack the repository: \(result.errorOutput)"])
        }
        try FileManager.default.moveItem(at: partial, to: folder)
    }

    /// Source files in a language Riviu can parse, skipping dependencies, build output and huge files.
    private func readSourceFiles(in folder: URL) throws -> [(path: String, text: String)] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return [] }
        var files: [(path: String, text: String)] = []
        let prefixLength = folder.standardizedFileURL.path.count + 1
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if Self.skippedFolders.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            guard let language = SyntaxLanguage.detect(path: url.path), language != .json, language != .markdown,
                  (values?.fileSize ?? 0) <= Self.maxFileBytes,
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            files.append((String(url.standardizedFileURL.path.dropFirst(prefixLength)), text))
            if files.count >= Self.maxFiles { break }
        }
        return files
    }
}
