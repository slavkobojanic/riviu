/// A guided tour of a pull request, as the AI returns it: the few places worth reading, in order.
public struct TourReport: Decodable, Sendable, Equatable {
    public struct Stop: Decodable, Sendable, Equatable {
        /// Groups stops, like "Core change" or "Callers".
        public let chapter: String
        public let title: String
        public let explanation: String
        public let file: String
        public let side: ReviewReport.Side
        /// 1-based, inclusive.
        public let startLine: Int
        public let endLine: Int
    }

    public let stops: [Stop]
    /// A sentence about what the tour leaves out, like "Generated jOOQ records and test fixtures."
    public let rest: String?

    public static let maxStops = 8

    public static let formatInstructions = """
    Reply with only a JSON object, no other text, in this shape:
    {"stops": [{"chapter": "Core change", "title": "Short title", "explanation": "Why this matters and what to check.", \
    "file": "path/to/file", "side": "new", "startLine": 12, "endLine": 30}], \
    "rest": "One sentence on what the tour leaves out."}
    Pick only the places a reviewer must read to understand and judge the change: at most \(maxStops) stops, fewer \
    when the change is small. Leave out renames, imports, formatting, generated code and routine tests; "rest" \
    names them in one sentence. Each stop is one range of at most 30 lines that appears in the diff, numbered as \
    shown: "side" is "new" for lines in the new file, or "old" for lines that were removed. Order the stops the way \
    to read them: the core change first, then the code that uses it, then anything risky. Use 2 to 4 chapter names \
    and keep stops of a chapter together. Explanations are at most 50 words, plain sentences, `code` in backticks.
    """

    public static func parse(_ reply: String) throws -> TourReport {
        try ReviewReport.decodeJSON(TourReport.self, in: reply)
    }
}
