import Foundation

public enum GitHubError: LocalizedError, Equatable {
    case unauthorized
    case rateLimited
    case notFound
    case rejected(String)
    case requestFailed(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: "GitHub didn't accept the sign-in. Sign in again in Settings → GitHub."
        case .rateLimited: "GitHub's rate limit was reached. Try again in a few minutes."
        case .notFound: "GitHub couldn't find that. You may not have access to it."
        case let .rejected(message): message
        case let .requestFailed(status, message): "GitHub request failed (\(status)): \(message)"
        }
    }
}

/// A small client for the parts of the GitHub REST API that Riviu uses.
public struct GitHubClient: Sendable {
    static let apiURL = URL(string: "https://api.github.com")!

    public let token: String

    public init(token: String) {
        self.token = token
    }

    public func currentUser() async throws -> GitHubUser {
        try await get("user")
    }

    public func searchPullRequests(_ query: PullRequestQuery) async throws -> [GitHubPullRequestSummary] {
        struct SearchResults: Decodable {
            let items: [GitHubPullRequestSummary]
        }
        let results: SearchResults = try await get("search/issues", query: [
            URLQueryItem(name: "q", value: query.searchString),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "per_page", value: "50"),
        ])
        return results.items
    }

    public func pullRequest(repository: String, number: Int) async throws -> GitHubPullRequest {
        try await get("repos/\(repository)/pulls/\(number)")
    }

    /// Every changed file, following pages of 100. GitHub stops at 3,000 files.
    public func changedFiles(repository: String, number: Int) async throws -> [GitHubChangedFile] {
        var files: [GitHubChangedFile] = []
        for page in 1...30 {
            let batch: [GitHubChangedFile] = try await get("repos/\(repository)/pulls/\(number)/files", query: [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: String(page)),
            ])
            files += batch
            if batch.count < 100 { break }
        }
        return files
    }

    /// The commit the pull request's changes are measured from: where its branch split off the base branch.
    public func mergeBase(repository: String, base: String, head: String) async throws -> String {
        struct Comparison: Decodable {
            struct Commit: Decodable { let sha: String }
            let mergeBaseCommit: Commit
        }
        let comparison: Comparison = try await get("repos/\(repository)/compare/\(base)...\(head)", query: [
            URLQueryItem(name: "per_page", value: "1"),
        ])
        return comparison.mergeBaseCommit.sha
    }

    public func issue(repository: String, number: Int) async throws -> GitHubIssue {
        try await get("repos/\(repository)/issues/\(number)")
    }

    /// A file's raw contents at a commit.
    public func fileContents(repository: String, path: String, ref: String) async throws -> Data {
        var components = URLComponents(url: Self.apiURL.appending(path: "repos/\(repository)/contents/\(path)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "ref", value: ref)]
        var request = makeRequest(url: components.url!)
        request.setValue("application/vnd.github.raw+json", forHTTPHeaderField: "Accept")
        return try await send(request)
    }

    public func submitReview(_ review: GitHubReviewSubmission, repository: String, number: Int) async throws {
        var request = makeRequest(url: Self.apiURL.appending(path: "repos/\(repository)/pulls/\(number)/reviews"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(review)
        _ = try await send(request)
    }

    // MARK: - Requests

    private func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        var components = URLComponents(url: Self.apiURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query
        }
        let data = try await send(makeRequest(url: components.url!))
        return try Self.decoder.decode(Response.self, from: data)
    }

    func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw GitHubError.unauthorized
        case 403 where http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0", 429:
            throw GitHubError.rateLimited
        case 404:
            throw GitHubError.notFound
        case 422:
            throw GitHubError.rejected(Self.errorMessage(in: data))
        default:
            throw GitHubError.requestFailed(status: http.statusCode, message: Self.errorMessage(in: data))
        }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// GitHub errors look like `{"message": "Validation Failed", "errors": ["…"]}`.
    static func errorMessage(in data: Data) -> String {
        struct ErrorBody: Decodable {
            let message: String
            let errors: [Detail]?
        }
        enum Detail: Decodable {
            case text(String)
            case object(message: String?)

            init(from decoder: Decoder) throws {
                if let text = try? decoder.singleValueContainer().decode(String.self) {
                    self = .text(text)
                } else {
                    struct Object: Decodable { let message: String? }
                    self = .object(message: try Object(from: decoder).message)
                }
            }

            var message: String? {
                switch self {
                case let .text(text): text
                case let .object(message): message
                }
            }
        }
        guard let body = try? JSONDecoder().decode(ErrorBody.self, from: data) else {
            return String(decoding: data, as: UTF8.self)
        }
        let details = body.errors?.compactMap(\.message) ?? []
        return ([body.message] + details).joined(separator: ": ")
    }
}
