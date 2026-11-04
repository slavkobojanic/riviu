import Foundation

/// One CI job or check on a commit, like "test (macos-15)".
public struct GitHubCheckRun: Decodable, Sendable, Identifiable, Hashable {
    public struct Output: Decodable, Sendable, Hashable {
        public let title: String?
        public let annotationsCount: Int
    }

    public struct App: Decodable, Sendable, Hashable {
        public let slug: String
    }

    public let id: Int
    public let name: String
    /// queued, in_progress or completed.
    public let status: String
    /// success, failure, neutral, cancelled, skipped, timed_out or action_required, once completed.
    public let conclusion: String?
    public let htmlUrl: URL?
    public let output: Output
    public let app: App?

    public init(id: Int, name: String, status: String, conclusion: String?, htmlUrl: URL? = nil,
                annotationsCount: Int = 0, appSlug: String? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.conclusion = conclusion
        self.htmlUrl = htmlUrl
        output = Output(title: nil, annotationsCount: annotationsCount)
        app = appSlug.map(App.init)
    }

    public var isFailure: Bool { ["failure", "timed_out", "action_required"].contains(conclusion ?? "") }
    public var isRunning: Bool { status != "completed" }
    /// GitHub Actions jobs have logs Riviu can read; their check run ID is the job ID.
    public var hasLogs: Bool { app?.slug == "github-actions" }
}

/// A message a check left on some lines, like a lint warning or a failed assertion.
public struct GitHubCheckAnnotation: Decodable, Sendable, Hashable {
    public let path: String
    public let startLine: Int
    public let endLine: Int
    /// notice, warning or failure.
    public let annotationLevel: String
    public let title: String?
    public let message: String

    public init(path: String, startLine: Int, endLine: Int, annotationLevel: String, title: String?, message: String) {
        self.path = path
        self.startLine = startLine
        self.endLine = endLine
        self.annotationLevel = annotationLevel
        self.title = title
        self.message = message
    }
}

extension GitHubClient {
    public func checkRuns(repository: String, commit: String) async throws -> [GitHubCheckRun] {
        struct Response: Decodable { let checkRuns: [GitHubCheckRun] }
        let response: Response = try await get("repos/\(repository)/commits/\(commit)/check-runs", query: [
            URLQueryItem(name: "per_page", value: "100"),
        ])
        return response.checkRuns
    }

    public func annotations(repository: String, checkRunID: Int) async throws -> [GitHubCheckAnnotation] {
        try await get("repos/\(repository)/check-runs/\(checkRunID)/annotations", query: [
            URLQueryItem(name: "per_page", value: "100"),
        ])
    }

    /// The end of a GitHub Actions job's log, where failures usually are.
    public func jobLogTail(repository: String, jobID: Int, maxCharacters: Int = 12_000) async throws -> String {
        let request = makeRequest(url: Self.apiURL.appending(path: "repos/\(repository)/actions/jobs/\(jobID)/logs"))
        let log = String(decoding: try await send(request), as: UTF8.self)
        return String(log.suffix(maxCharacters))
    }
}
