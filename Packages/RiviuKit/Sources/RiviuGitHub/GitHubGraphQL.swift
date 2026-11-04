import Foundation

/// Whether you've marked a file as viewed on GitHub. `dismissed` means it changed after you viewed it.
public enum GitHubViewedState: String, Decodable, Sendable {
    case viewed = "VIEWED"
    case unviewed = "UNVIEWED"
    case dismissed = "DISMISSED"
}

/// The viewed state of every file in a pull request, plus the pull request's GraphQL ID, which edits need.
public struct GitHubViewedFiles: Sendable {
    public let pullRequestID: String
    public let states: [String: GitHubViewedState]
}

/// A conversation on some lines of a pull request.
public struct GitHubReviewThread: Decodable, Sendable, Identifiable {
    public struct Comment: Decodable, Sendable, Identifiable {
        public struct Author: Decodable, Sendable {
            public let login: String
        }

        public let id: String
        /// nil for a deleted account.
        public let author: Author?
        public let body: String
        public let createdAt: Date
    }

    struct Comments: Decodable, Sendable {
        let nodes: [Comment]
    }

    public let id: String
    public let isResolved: Bool
    /// True when the lines it was on have since changed.
    public let isOutdated: Bool
    public let path: String
    /// 1-based last line in the latest diff, or nil when the thread is outdated.
    public let line: Int?
    /// "LEFT" is the base version, "RIGHT" the head version.
    public let diffSide: String
    let comments: Comments

    public var allComments: [Comment] { comments.nodes }
}

/// The parts of GitHub's GraphQL API that the REST API doesn't cover: viewed files and review threads.
extension GitHubClient {
    public func viewedFiles(repository: String, number: Int) async throws -> GitHubViewedFiles {
        struct Response: Decodable {
            struct Repository: Decodable { let pullRequest: PullRequest }
            struct PullRequest: Decodable {
                let id: String
                let files: Files
            }
            struct Files: Decodable {
                let nodes: [File]
                let pageInfo: PageInfo
            }
            struct File: Decodable {
                let path: String
                let viewerViewedState: GitHubViewedState
            }
            let repository: Repository
        }
        let query = """
        query($owner: String!, $name: String!, $number: Int!, $after: String) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              id
              files(first: 100, after: $after) {
                nodes { path viewerViewedState }
                pageInfo { hasNextPage endCursor }
              }
            }
          }
        }
        """
        var states: [String: GitHubViewedState] = [:]
        var pullRequestID = ""
        var cursor: String?
        for _ in 1...30 {
            let response: Response = try await graphQL(query, variables: PullRequestVariables(repository: repository, number: number, after: cursor))
            pullRequestID = response.repository.pullRequest.id
            for file in response.repository.pullRequest.files.nodes {
                states[file.path] = file.viewerViewedState
            }
            let pageInfo = response.repository.pullRequest.files.pageInfo
            guard pageInfo.hasNextPage else { break }
            cursor = pageInfo.endCursor
        }
        return GitHubViewedFiles(pullRequestID: pullRequestID, states: states)
    }

    public func setFileViewed(_ isViewed: Bool, path: String, pullRequestID: String) async throws {
        struct Variables: Encodable, Sendable {
            let pullRequestId: String
            let path: String
        }
        let mutation = isViewed ? "markFileAsViewed" : "unmarkFileAsViewed"
        let query = """
        mutation($pullRequestId: ID!, $path: String!) {
          \(mutation)(input: { pullRequestId: $pullRequestId, path: $path }) { clientMutationId }
        }
        """
        let _: EmptyResponse = try await graphQL(query, variables: Variables(pullRequestId: pullRequestID, path: path))
    }

    /// Every review thread, with up to 50 comments each.
    public func reviewThreads(repository: String, number: Int) async throws -> [GitHubReviewThread] {
        struct Response: Decodable {
            struct Repository: Decodable { let pullRequest: PullRequest }
            struct PullRequest: Decodable { let reviewThreads: Threads }
            struct Threads: Decodable {
                let nodes: [GitHubReviewThread]
                let pageInfo: PageInfo
            }
            let repository: Repository
        }
        let query = """
        query($owner: String!, $name: String!, $number: Int!, $after: String) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              reviewThreads(first: 50, after: $after) {
                nodes {
                  id isResolved isOutdated path line diffSide
                  comments(first: 50) { nodes { id author { login } body createdAt } }
                }
                pageInfo { hasNextPage endCursor }
              }
            }
          }
        }
        """
        var threads: [GitHubReviewThread] = []
        var cursor: String?
        for _ in 1...20 {
            let response: Response = try await graphQL(query, variables: PullRequestVariables(repository: repository, number: number, after: cursor))
            threads += response.repository.pullRequest.reviewThreads.nodes
            let pageInfo = response.repository.pullRequest.reviewThreads.pageInfo
            guard pageInfo.hasNextPage else { break }
            cursor = pageInfo.endCursor
        }
        return threads
    }

    public func reply(to threadID: String, body: String) async throws -> GitHubReviewThread.Comment {
        struct Variables: Encodable, Sendable {
            let threadId: String
            let body: String
        }
        struct Response: Decodable {
            struct Payload: Decodable { let comment: GitHubReviewThread.Comment }
            let addPullRequestReviewThreadReply: Payload
        }
        let query = """
        mutation($threadId: ID!, $body: String!) {
          addPullRequestReviewThreadReply(input: { pullRequestReviewThreadId: $threadId, body: $body }) {
            comment { id author { login } body createdAt }
          }
        }
        """
        let response: Response = try await graphQL(query, variables: Variables(threadId: threadID, body: body))
        return response.addPullRequestReviewThreadReply.comment
    }

    public func setThreadResolved(_ isResolved: Bool, threadID: String) async throws {
        struct Variables: Encodable, Sendable { let threadId: String }
        let mutation = isResolved ? "resolveReviewThread" : "unresolveReviewThread"
        let query = """
        mutation($threadId: ID!) {
          \(mutation)(input: { threadId: $threadId }) { thread { id } }
        }
        """
        let _: EmptyResponse = try await graphQL(query, variables: Variables(threadId: threadID))
    }

    // MARK: - Requests

    func graphQL<Variables: Encodable & Sendable, Response: Decodable>(_ query: String, variables: Variables) async throws -> Response {
        var request = makeRequest(url: Self.apiURL.appending(path: "graphql"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GraphQLBody(query: query, variables: variables))
        let reply = try Self.decoder.decode(GraphQLReply<Response>.self, from: try await send(request))
        if let problem = reply.errors?.first {
            throw GitHubError.rejected(problem.message)
        }
        guard let data = reply.data else { throw GitHubError.rejected("GitHub returned no data.") }
        return data
    }
}

private struct PullRequestVariables: Encodable, Sendable {
    let owner: String
    let name: String
    let number: Int
    let after: String?

    init(repository: String, number: Int, after: String?) {
        let parts = repository.split(separator: "/", maxSplits: 1)
        owner = parts.first.map(String.init) ?? ""
        name = parts.count > 1 ? String(parts[1]) : ""
        self.number = number
        self.after = after
    }
}

private struct GraphQLBody<Variables: Encodable>: Encodable {
    let query: String
    let variables: Variables
}

/// GraphQL replies with 200 even when it fails, listing the problems in `errors`.
struct GraphQLReply<Response: Decodable>: Decodable {
    struct Problem: Decodable { let message: String }
    let data: Response?
    let errors: [Problem]?
}

struct PageInfo: Decodable {
    let hasNextPage: Bool
    let endCursor: String?
}

/// For mutations whose reply Riviu doesn't need.
private struct EmptyResponse: Decodable {}
