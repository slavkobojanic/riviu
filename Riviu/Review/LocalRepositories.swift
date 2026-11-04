import Foundation
import RiviuGitHub
import RiviuSupport

/// Riviu's own copies of GitHub repositories, so file contents come from disk instead of one API call each.
///
/// Each repository is a bare, blobless clone in Application Support: commits and folder listings are downloaded,
/// file contents only when they're needed. The user's own checkouts are never touched.
/// Pull requests in the sidebar are fetched in the background, so opening one doesn't wait for the network.
actor LocalRepositories {
    enum GitError: LocalizedError {
        case failed(command: String, message: String)

        var errorDescription: String? {
            switch self {
            case let .failed(command, message): "git \(command) failed: \(message)"
            }
        }
    }

    /// Bigger repositories (GitHub's size, in kilobytes, of the whole history) are read through the API instead.
    private static let maxRepositoryKilobytes = 2_000_000
    /// How many pull requests from the list are fetched ahead of time.
    private static let maxPrefetchedPullRequests = 15

    private let folder = URL.applicationSupportDirectory.appending(path: "Riviu/Repositories", directoryHint: .isDirectory)
    /// The latest clone or fetch of each repository, so the next one can wait for it.
    private var downloads: [String: Task<Void, Error>] = [:]
    /// Head commits already fetched with their changed files, so the background fetch skips them.
    private var prefetchedHeads: Set<String> = []
    private var prefetchQueue: [GitHubPullRequestSummary] = []
    private var isPrefetching = false

    // MARK: - Reading

    nonisolated func isCloned(_ repository: String) -> Bool {
        FileManager.default.fileExists(atPath: path(of: repository).appending(path: "HEAD").path)
    }

    /// A file at a commit, or an error when the repository or commit isn't here.
    func contents(of filePath: String, at commit: String, in repository: String, token: String) async throws -> Data {
        guard isCloned(repository) else { throw GitError.failed(command: "cat-file", message: "not cloned") }
        return try await git(["cat-file", "blob", "\(commit):\(filePath)"], in: repository, token: token)
    }

    func mergeBase(of base: String, and head: String, in repository: String) async throws -> String {
        let output = try await git(["merge-base", base, head], in: repository, token: nil)
        return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Downloading

    /// Makes sure both commits of a pull request are on disk. A repository that isn't cloned yet starts
    /// cloning in the background and this returns false, so the caller can use the API meanwhile.
    func prepare(_ pullRequest: GitHubPullRequest, number: Int, repository: String, client: GitHubClient) async -> Bool {
        guard isCloned(repository) else {
            Task { try? await clone(repository, client: client) }
            return false
        }
        do {
            try await fetch(pullRequest, number: number, repository: repository, token: client.token)
            return true
        } catch {
            return false
        }
    }

    /// Fetches pull requests ahead of time, one at a time, in the order they were asked for.
    /// Ones already waiting aren't added twice.
    func prefetch(_ summaries: [GitHubPullRequestSummary], client: GitHubClient) {
        let open = summaries.filter { $0.state == "open" }.prefix(Self.maxPrefetchedPullRequests)
        for summary in open where !prefetchQueue.contains(where: { $0.id == summary.id }) {
            prefetchQueue.append(summary)
        }
        guard !isPrefetching else { return }
        isPrefetching = true
        Task {
            while !prefetchQueue.isEmpty {
                await prefetch(prefetchQueue.removeFirst(), client: client)
            }
            isPrefetching = false
        }
    }

    private func prefetch(_ summary: GitHubPullRequestSummary, client: GitHubClient) async {
        let repository = summary.repository
        do {
            let pullRequest = try await client.pullRequest(repository: repository, number: summary.number)
            guard !prefetchedHeads.contains(pullRequest.head.sha) else { return }
            if !isCloned(repository) {
                try await clone(repository, client: client)
            }
            try await fetch(pullRequest, number: summary.number, repository: repository, token: client.token)
            // Diffing the two commits downloads every changed file's contents in one batch.
            let base = try await mergeBase(of: pullRequest.base.sha, and: pullRequest.head.sha, in: repository)
            _ = try await git(["diff", "--output=/dev/null", "-p", base, pullRequest.head.sha], in: repository, token: client.token)
            prefetchedHeads.insert(pullRequest.head.sha)
        } catch {
            // Not worth bothering anyone: opening the pull request falls back to the API.
        }
    }

    private func clone(_ repository: String, client: GitHubClient) async throws {
        try await download(repository) {
            // An earlier request may have cloned it while this one waited.
            if self.isCloned(repository) { return }
            if let size = try? await client.repositorySize(repository), size > Self.maxRepositoryKilobytes {
                throw GitError.failed(command: "clone", message: "\(repository) is too big to keep a copy of")
            }
            let destination = self.path(of: repository)
            let partial = destination.appendingPathExtension("partial")
            try? FileManager.default.removeItem(at: partial)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try await self.run(["clone", "--bare", "--filter=blob:none", "--single-branch", "--no-tags",
                                    "https://github.com/\(repository).git", partial.path],
                                   in: nil, token: client.token)
            try FileManager.default.moveItem(at: partial, to: destination)
        }
    }

    /// Downloads the pull request's head and its base branch, unless both commits are already here.
    private func fetch(_ pullRequest: GitHubPullRequest, number: Int, repository: String, token: String) async throws {
        if await hasCommit(pullRequest.head.sha, in: repository), await hasCommit(pullRequest.base.sha, in: repository) {
            return
        }
        try await download(repository) {
            _ = try await self.git(["fetch", "--no-tags", "origin",
                                    "+refs/pull/\(number)/head:refs/pull/\(number)/head",
                                    "+refs/heads/\(pullRequest.base.ref):refs/heads/\(pullRequest.base.ref)"],
                                   in: repository, token: token)
        }
    }

    private func hasCommit(_ sha: String, in repository: String) async -> Bool {
        (try? await git(["cat-file", "-e", "\(sha)^{commit}"], in: repository, token: nil)) != nil
    }

    /// Runs one download per repository at a time: each one waits for the one before it to finish.
    private func download(_ repository: String, _ work: @escaping @Sendable () async throws -> Void) async throws {
        let previous = downloads[repository]
        let task = Task {
            _ = try? await previous?.value
            try await work()
        }
        downloads[repository] = task
        try await task.value
    }

    // MARK: - Running git

    private nonisolated func path(of repository: String) -> URL {
        folder.appending(path: "\(repository).git", directoryHint: .isDirectory)
    }

    private func git(_ arguments: [String], in repository: String, token: String?) async throws -> Data {
        try await run(arguments, in: path(of: repository), token: token)
    }

    /// Runs git with only Riviu's settings: the user's own git config (like rewriting https to ssh)
    /// and their saved credentials are left out, and the GitHub token is passed in the environment.
    private func run(_ arguments: [String], in directory: URL?, token: String?) async throws -> Data {
        var environment = ExecutableLocator.environment
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        var settings = ["credential.helper": ""]
        if let token {
            let credentials = Data("x-access-token:\(token)".utf8).base64EncodedString()
            settings["http.https://github.com/.extraheader"] = "Authorization: Basic \(credentials)"
        }
        environment["GIT_CONFIG_COUNT"] = String(settings.count)
        for (index, setting) in settings.sorted(by: { $0.key < $1.key }).enumerated() {
            environment["GIT_CONFIG_KEY_\(index)"] = setting.key
            environment["GIT_CONFIG_VALUE_\(index)"] = setting.value
        }

        let gitArguments = directory.map { ["--git-dir", $0.path] + arguments } ?? arguments
        let result = try await ProcessRunner.run(Self.gitURL, arguments: gitArguments, environment: environment)
        guard result.status == 0 else {
            throw GitError.failed(command: arguments.first ?? "", message: String(decoding: result.errorOutput, as: UTF8.self))
        }
        return result.output
    }

    private static let gitURL = ExecutableLocator.find("git") ?? URL(filePath: "/usr/bin/git")
}

/// Runs a command to completion, keeping its output as raw bytes (file contents can be binary).
nonisolated enum ProcessRunner {
    struct Result: Sendable {
        let status: Int32
        let output: Data
        let errorOutput: Data
    }

    static func run(_ executable: URL, arguments: [String], environment: [String: String]) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        // Both pipes are read at once: if one fills up while nobody reads it, the command stalls.
        let outputHandle = output.fileHandleForReading
        let errorHandle = errors.fileHandleForReading
        async let outputData = Task.detached { outputHandle.readDataToEndOfFile() }.value
        async let errorData = Task.detached { errorHandle.readDataToEndOfFile() }.value
        let (outputBytes, errorBytes) = await (outputData, errorData)
        await Task.detached { process.waitUntilExit() }.value
        return Result(status: process.terminationStatus, output: outputBytes, errorOutput: errorBytes)
    }
}
