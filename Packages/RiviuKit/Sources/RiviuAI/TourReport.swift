/// A guided tour of a pull request, as the AI returns it: chapters of hunk IDs in reading order.
public struct TourReport: Decodable, Sendable, Equatable {
    public struct Chapter: Decodable, Sendable, Equatable {
        public let title: String
        /// Why this chapter matters, in a sentence or two.
        public let why: String
        /// Hunk IDs like "H3", in the order to read them.
        public let hunks: [String]
    }

    public let chapters: [Chapter]

    public static let formatInstructions = """
    Reply with only a JSON object, no other text, in this shape:
    {"chapters": [{"title": "Short title", "why": "What this part does and what to check. At most 30 words.", "hunks": ["H3", "H1"]}]}
    Make 3 to 7 chapters in the order a reviewer should read them: the core change first, then the code that calls it,
    then tests. Put renames, import changes, formatting and generated files together in a last chapter titled
    "Small stuff". Use each hunk ID at most once.
    """

    public static func parse(_ reply: String) throws -> TourReport {
        try ReviewReport.decodeJSON(TourReport.self, in: reply)
    }
}
