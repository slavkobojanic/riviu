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
        public let side: Side
        public let severity: Level
        public let title: String
        public let body: String

        private enum CodingKeys: String, CodingKey {
            case file, line, side, severity, title, body
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            file = try container.decode(String.self, forKey: .file)
            line = try container.decode(Int.self, forKey: .line)
            side = try container.decodeIfPresent(Side.self, forKey: .side) ?? .new
            severity = try container.decode(Level.self, forKey: .severity)
            title = try container.decode(String.self, forKey: .title)
            body = try container.decode(String.self, forKey: .body)
        }
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

    /// Tells the model exactly what to reply with.
    public static let formatInstructions = """
    Reply with only a JSON object, no other text, in this shape:
    {
      "summary": "Markdown: what the pull request does and anything a reviewer should look at first. At most 150 words.",
      "risk": "low" | "medium" | "high",
      "findings": [
        {
          "file": "path/of/the/file",
          "line": 42,
          "side": "new" | "old",
          "severity": "low" | "medium" | "high",
          "title": "Short headline",
          "body": "Markdown: what is wrong and how to fix it. At most 60 words."
        }
      ]
    }
    Lines in the diffs are numbered. Use "side": "old" only for a line starting with "-"; its number is in the old file.
    Every other line is numbered in the new file. Only report real problems: bugs, security issues, missing tests for risky code,
    and confusing code. Return an empty findings list if there are none.
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
