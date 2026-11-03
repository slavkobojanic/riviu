/// Filters for the pull request list, turned into a GitHub search query.
public struct PullRequestQuery: Equatable, Sendable, Codable {
    public enum Involvement: String, CaseIterable, Sendable, Codable {
        case reviewRequested, assigned, authored, mentioned, involved

        public var title: String {
            switch self {
            case .reviewRequested: "Review requested"
            case .assigned: "Assigned to me"
            case .authored: "Created by me"
            case .mentioned: "Mentioning me"
            case .involved: "Involving me"
            }
        }

        var qualifier: String {
            switch self {
            case .reviewRequested: "review-requested:@me"
            case .assigned: "assignee:@me"
            case .authored: "author:@me"
            case .mentioned: "mentions:@me"
            case .involved: "involves:@me"
            }
        }
    }

    public enum State: String, CaseIterable, Sendable, Codable {
        case open, merged, closed, all

        public var title: String { rawValue.capitalized }

        var qualifier: String? {
            switch self {
            case .open: "is:open"
            case .merged: "is:merged"
            case .closed: "is:closed is:unmerged"
            case .all: nil
            }
        }
    }

    public var involvement: Involvement = .reviewRequested
    public var state: State = .open
    /// "owner/name", or nil for every repository.
    public var repository: String?
    /// Extra search text, which can include GitHub qualifiers such as `label:bug`.
    public var text = ""

    public init() {}

    /// For example `is:pr archived:false review-requested:@me is:open repo:apple/swift flaky`.
    public var searchString: String {
        var parts = ["is:pr", "archived:false", involvement.qualifier]
        if let qualifier = state.qualifier {
            parts.append(qualifier)
        }
        if let repository, !repository.isEmpty {
            parts.append("repo:\(repository)")
        }
        let text = text.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            parts.append(text)
        }
        return parts.joined(separator: " ")
    }
}
