import Foundation

/// What an AI review of a pull request returns: a summary, an overall risk and line-level findings.
///
/// The model is asked to reply with JSON in this shape (see `ReviewReport.formatInstructions`).
public struct ReviewReport: Decodable, Sendable, Equatable {
    public enum Level: String, Decodable, Sendable {
        case low, medium, high
    }

    public enum Side: String, Decodable, Sendable {
        case old, new
    }

    public struct Finding: Decodable, Sendable, Equatable {
        public let file: String
        /// 1-based, in the old file for `side == .old`, otherwise in the new file.
        public let line: Int
        /// The last line of a finding that spans several lines.
        public let endLine: Int?
        public let side: Side
        public let severity: Level
        public let title: String
        public let body: String
        /// Replacement code for lines `line...endLine` of the new file, posted as a GitHub suggestion.
        public let suggestion: String?

        private enum CodingKeys: String, CodingKey {
            case file, line, endLine, side, severity, title, body, suggestion
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            file = try container.decode(String.self, forKey: .file)
            line = try container.decode(Int.self, forKey: .line)
            side = try container.decodeIfPresent(Side.self, forKey: .side) ?? .new
            severity = try container.decode(Level.self, forKey: .severity)
            title = try container.decode(String.self, forKey: .title)
            body = try container.decode(String.self, forKey: .body)
            endLine = try container.decodeIfPresent(Int.self, forKey: .endLine)
            suggestion = try container.decodeIfPresent(String.self, forKey: .suggestion)
        }
    }

    /// Whether the change does what its description and linked issues ask for.
    public struct SpecCheck: Codable, Sendable, Equatable {
        public enum Status: String, Codable, Sendable {
            case addressed, partial, missing
        }

        public struct Goal: Codable, Sendable, Equatable {
            public let goal: String
            public let status: Status
            /// Where it's done, or what's missing.
            public let note: String

            public init(goal: String, status: Status, note: String) {
                self.goal = goal
                self.status = status
                self.note = note
            }
        }

        public let goals: [Goal]
        /// Changes nobody asked for.
        public let unrequested: [String]
        /// Set when the description is too thin to check against.
        public let tooVagueToCheck: Bool?

        public init(goals: [Goal], unrequested: [String], tooVagueToCheck: Bool? = nil) {
            self.goals = goals
            self.unrequested = unrequested
            self.tooVagueToCheck = tooVagueToCheck
        }
    }

    /// Something only the author can answer, on a line.
    public struct Question: Decodable, Sendable, Equatable {
        public let file: String
        public let line: Int
        public let question: String
    }

    /// What happened to a finding from an earlier review, after new commits.
    public struct PreviousFinding: Decodable, Sendable, Equatable {
        public enum Status: String, Decodable, Sendable {
            case addressed, open
        }

        /// Its number in the earlier review's list.
        public let index: Int
        public let status: Status
        /// Where an open finding is now, 1-based in the new file.
        public let line: Int?
    }

    public enum ParseError: LocalizedError {
        case noJSON
        case invalid(String)

        public var errorDescription: String? {
            switch self {
            case .noJSON: "The AI didn't reply with a review. Try again, or pick a different model in Settings → AI."
            case let .invalid(detail): "The AI's review couldn't be read: \(detail)"
            }
        }
    }

    /// A short Markdown overview of the change.
    public let summary: String
    public let risk: Level
    public let findings: [Finding]
    public let specCheck: SpecCheck?
    public let questions: [Question]?
    /// Only for a re-review after new commits.
    public let previousFindings: [PreviousFinding]?

    /// Tells the model exactly what to reply with.
    public static let formatInstructions = """
    Reply with only a JSON object, no other text, in this shape:
    {
      "summary": "Markdown: what the pull request does and anything a reviewer should look at first. At most 150 words.",
      "risk": "low" | "medium" | "high",
      "specCheck": {
        "goals": [{"goal": "One thing the description or a linked issue asks for", "status": "addressed" | "partial" | "missing", "note": "Where it is done, or what is missing. At most 25 words."}],
        "unrequested": ["A change nobody asked for, in at most 20 words"],
        "tooVagueToCheck": false
      },
      "questions": [{"file": "path/of/the/file", "line": 42, "question": "Something only the author can answer"}],
      "findings": [
        {
          "file": "path/of/the/file",
          "line": 42,
          "endLine": 44,
          "side": "new" | "old",
          "severity": "low" | "medium" | "high",
          "title": "Short headline",
          "body": "Markdown: what is wrong and how to fix it. At most 60 words.",
          "suggestion": "The fixed code that replaces lines line through endLine, exactly as it should read."
        }
      ]
    }
    Lines in the diffs are numbered. Use "side": "old" only for a line starting with "-"; its number is in the old file.
    Every other line is numbered in the new file. "endLine" is optional, for a finding that spans several lines.
    Add "suggestion" only for a small, certain fix to new-file lines from one hunk; keep the original indentation. Only report real problems: bugs, security issues, missing tests for risky code,
    and confusing code. Return an empty findings list if there are none.
    For specCheck, list each goal from the description and linked issues (at most 6). If the description is too thin to
    check against, set "tooVagueToCheck": true and leave goals empty rather than guessing. List unrequested changes only
    when they are real behaviour changes. Ask at most 3 questions, only about intent or context the diff can't answer,
    each on a new-file line; ask none if nothing is unclear.
    """

    /// Added to the format when an earlier review's findings are sent along.
    public static let previousFindingsInstructions = """
    Also add "previousFindings": [{"index": 0, "status": "addressed" | "open", "line": 42}], with one entry for every \
    earlier finding. Use "addressed" only when the new commits fix it. For "open", give its current new-file line.
    Report new findings only for lines changed since the earlier review.
    """

    /// Reads the JSON object out of a reply, ignoring any text or code fence around it.
    public static func parse(_ reply: String) throws -> ReviewReport {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end else {
            throw ParseError.noJSON
        }
        let json = Data(reply[start...end].utf8)
        do {
            return try JSONDecoder().decode(ReviewReport.self, from: json)
        } catch let DecodingError.dataCorrupted(context) {
            throw ParseError.invalid(context.debugDescription)
        } catch let DecodingError.keyNotFound(key, _) {
            throw ParseError.invalid("“\(key.stringValue)” is missing.")
        } catch {
            throw ParseError.invalid(error.localizedDescription)
        }
    }
}
