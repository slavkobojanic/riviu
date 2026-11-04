import Foundation

/// The AI's one-line description of each hop on a hot path: what happens going from one step to the next.
public struct HotPathHops: Decodable, Sendable, Equatable {
    /// `hops[i]` describes the hop from step i to step i + 1.
    public let hops: [String]

    public init(hops: [String]) {
        self.hops = hops
    }

    /// Reads `{"hops": [...]}` out of a reply, ignoring text or a code fence around it. Empty descriptions are
    /// kept as empty strings so the rest still line up with their hops.
    public static func parse(_ reply: String) throws -> HotPathHops {
        let decoded = try ReviewReport.decodeJSON(HotPathHops.self, in: reply)
        return HotPathHops(hops: decoded.hops.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }
}
