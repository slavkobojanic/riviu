import Foundation

/// What kind of edit a changed hunk is. Anything not certainly cosmetic is `logic`.
public enum StructuralChange: String, Sendable, Hashable {
    /// The same lines, removed in one place and added in another.
    case moved
    /// Only names changed, each one consistently, like `count` → `total` everywhere in the hunk.
    case renameOnly
    /// The same code with different whitespace or line breaks.
    case formattingOnly
    case logic

    public var title: String {
        switch self {
        case .moved: "Moved"
        case .renameOnly: "Rename only"
        case .formattingOnly: "Formatting only"
        case .logic: "Logic"
        }
    }

    public var isCosmetic: Bool { self != .logic }
}

/// Labels each changed hunk of a file. A hunk is only called cosmetic on an exact token match, so a real logic
/// change is never hidden behind a "formatting only" label.
public enum StructuralChanges {
    /// The kind of every changed segment, by its index in `file.segments`.
    public static func classify(_ file: FileDiff) -> [Int: StructuralChange] {
        var result: [Int: StructuralChange] = [:]
        let blocks = movableBlocks(in: file)
        for (index, segment) in file.segments.enumerated() {
            guard case let .changed(removed, added) = segment else { continue }
            let old = Array(file.baseLines[removed])
            let new = Array(file.headLines[added])
            result[index] = classify(old: old, new: new, segmentIndex: index, blocks: blocks)
        }
        return result
    }

    private static func classify(old: [String], new: [String], segmentIndex: Int, blocks: [(segment: Int, isAdded: Bool, key: [String])]) -> StructuralChange {
        if old.isEmpty || new.isEmpty {
            // A removal is moved if the same lines were added elsewhere, and an addition if they were removed elsewhere.
            let isRemoval = new.isEmpty
            let key = normalized(isRemoval ? old : new)
            let isMoved = isWorthMatching(key) && blocks.contains { $0.segment != segmentIndex && $0.isAdded == isRemoval && $0.key == key }
            return isMoved ? .moved : .logic
        }
        let oldTokens = old.flatMap(tokens)
        let newTokens = new.flatMap(tokens)
        if oldTokens == newTokens {
            return .formattingOnly
        }
        if !containsComments(old + new), isConsistentRename(oldTokens, newTokens) {
            return .renameOnly
        }
        return .logic
    }

    // MARK: - Moved blocks

    /// Pure removals and pure additions, which could be either end of a move.
    private static func movableBlocks(in file: FileDiff) -> [(segment: Int, isAdded: Bool, key: [String])] {
        file.segments.enumerated().compactMap { index, segment in
            guard case let .changed(removed, added) = segment else { return nil }
            if added.isEmpty { return (index, false, normalized(Array(file.baseLines[removed]))) }
            if removed.isEmpty { return (index, true, normalized(Array(file.headLines[added]))) }
            return nil
        }
    }

    private static func normalized(_ lines: [String]) -> [String] {
        lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Short blocks like a lone "}" match by accident.
    private static func isWorthMatching(_ lines: [String]) -> Bool {
        lines.count >= 2 && lines.joined().count >= 20
    }

    // MARK: - Renames

    /// Same tokens except identifiers, where each old name always becomes the same new name and vice versa.
    private static func isConsistentRename(_ old: [Token], _ new: [Token]) -> Bool {
        guard old.count == new.count else { return false }
        var forward: [String: String] = [:]
        var backward: [String: String] = [:]
        for (a, b) in zip(old, new) where a != b {
            guard a.isIdentifier, b.isIdentifier else { return false }
            if let mapped = forward[a.text], mapped != b.text { return false }
            if let mapped = backward[b.text], mapped != a.text { return false }
            forward[a.text] = b.text
            backward[b.text] = a.text
        }
        return !forward.isEmpty
    }

    private static func containsComments(_ lines: [String]) -> Bool {
        lines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return ["//", "/*", "*", "#", "--"].contains { trimmed.hasPrefix($0) } || line.contains("//") || line.contains("/*")
        }
    }

    // MARK: - Tokens

    struct Token: Equatable {
        let text: String
        let isIdentifier: Bool
    }

    /// Identifiers, numbers, whole string literals and single punctuation characters; whitespace is dropped.
    static func tokens(_ line: String) -> [Token] {
        var result: [Token] = []
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
            } else if character == "\"" || character == "'" || character == "`" {
                let start = index
                index += 1
                while index < characters.count && characters[index] != character {
                    index += characters[index] == "\\" ? 2 : 1
                }
                index = min(index + 1, characters.count)
                result.append(Token(text: String(characters[start..<index]), isIdentifier: false))
            } else if character.isLetter || character == "_" || character.isNumber {
                let start = index
                while index < characters.count && (characters[index].isLetter || characters[index].isNumber || characters[index] == "_") {
                    index += 1
                }
                let word = String(characters[start..<index])
                result.append(Token(text: word, isIdentifier: !(word.first?.isNumber ?? false)))
            } else {
                result.append(Token(text: String(character), isIdentifier: false))
                index += 1
            }
        }
        return result
    }
}
