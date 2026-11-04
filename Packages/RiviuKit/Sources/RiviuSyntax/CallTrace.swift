import Foundation

/// One path through the code, read top to bottom like a stack trace: where it starts, the selected
/// function, and what it goes on to call.
public struct CallTrace: Sendable, Hashable {
    public struct Step: Sendable, Hashable {
        public let function: SymbolLocation
        /// The 0-based line in this function that calls the next step. nil on the last step.
        public let callLine: Int?
    }

    public let steps: [Step]
    /// Which step holds the selected code.
    public let focusIndex: Int
    /// True when something calls the first step too, but the trace stopped going up.
    public let hasMoreAbove: Bool
    /// True when the last step calls something more, but the trace stopped going down.
    public let hasMoreBelow: Bool
}

/// Builds a `CallTrace` from the symbol index.
///
/// The index only knows names, not types, so a call to `save` could mean any `save` in the repository.
/// To stay on the real path it only follows calls within the same language, skips tests, stories and
/// generated code, skips trivial getters and setters, and when a name is defined in several places it
/// picks the one the calling file actually mentions. At each step it prefers code this pull request changed.
public struct CallTracer: Sendable {
    public let index: SymbolIndex
    /// 0-based changed lines, by path, for the files in the pull request.
    public let changedLines: [String: Set<Int>]

    public static let maxStepsUp = 6
    public static let maxStepsDown = 6

    public init(index: SymbolIndex, changedLines: [String: Set<Int>]) {
        self.index = index
        self.changedLines = changedLines
    }

    /// The path through the selected lines, or nil when there's no function in or near them.
    public func trace(path: String, lines: ClosedRange<Int>) -> CallTrace? {
        guard let focus = focusFunction(path: path, lines: lines) else { return nil }
        var visited: Set<String> = [Self.key(focus)]

        // Walk up through callers until nothing calls the function any more.
        var above: [CallTrace.Step] = [] // nearest caller first
        var hasMoreAbove = false
        var current = focus
        while let caller = bestCaller(of: current, visited: visited) {
            if above.count == Self.maxStepsUp {
                hasMoreAbove = true
                break
            }
            above.append(CallTrace.Step(function: caller.function, callLine: caller.line))
            visited.insert(Self.key(caller.function))
            current = caller.function
        }

        // Walk down through the most relevant call at each step, starting with calls on the selected lines.
        var below: [SymbolLocation] = []
        var callLines: [Int] = [] // callLines[i] is where step i (focus first) calls step i + 1
        var hasMoreBelow = false
        current = focus
        var preferred: ClosedRange<Int>? = focus.path == path ? lines : nil
        while let callee = bestCallee(inside: current, preferring: preferred, visited: visited) {
            if below.count == Self.maxStepsDown {
                hasMoreBelow = true
                break
            }
            below.append(callee.function)
            callLines.append(callee.line)
            visited.insert(Self.key(callee.function))
            current = callee.function
            preferred = nil
        }

        var steps = Array(above.reversed())
        let downward = [focus] + below
        for (offset, function) in downward.enumerated() {
            steps.append(CallTrace.Step(function: function, callLine: offset < callLines.count ? callLines[offset] : nil))
        }
        return CallTrace(steps: steps, focusIndex: above.count, hasMoreAbove: hasMoreAbove, hasMoreBelow: hasMoreBelow)
    }

    // MARK: - Picking the function to start from

    /// The function the lines are in. Outside any function: the function called on those lines, or else the
    /// function nearest to them in the file.
    func focusFunction(path: String, lines: ClosedRange<Int>) -> SymbolLocation? {
        if let enclosing = index.enclosingDefinition(path: path, line: lines.lowerBound) {
            return enclosing
        }
        for call in index.calls(inside: lines, of: path) {
            if let definition = bestDefinition(named: call.name, calledFrom: path) {
                return definition
            }
        }
        func distance(_ function: SymbolLocation) -> Int {
            if function.lines.lowerBound > lines.upperBound { return function.lines.lowerBound - lines.upperBound }
            if function.lines.upperBound < lines.lowerBound { return lines.lowerBound - function.lines.upperBound }
            return 0
        }
        return index.callableDefinitions(inFile: path).min { distance($0) < distance($1) }
    }

    // MARK: - Going up

    /// The most likely caller of a function, and the line of the call.
    func bestCaller(of function: SymbolLocation, visited: Set<String>) -> (function: SymbolLocation, line: Int)? {
        let family = Self.languageFamily(of: function.path)
        let typeNames = typeNames(for: function)
        let isPrivate = isPrivate(function)
        var best: (caller: SymbolLocation, line: Int, score: Int)?
        for call in index.calls(to: function.name) {
            let line = call.lines.lowerBound
            guard Self.languageFamily(of: call.path) == family, !isExcluded(call.path),
                  !isPrivate || call.path == function.path,
                  !(call.path == function.path && function.lines.contains(line)),
                  let caller = index.enclosingDefinition(path: call.path, line: line),
                  !visited.contains(Self.key(caller)) else { continue }
            let knowsFunction = call.path == function.path || typeNames.contains { mentions(call.path, $0) }
            let sameFolder = Self.folder(call.path) == Self.folder(function.path)
            // Code in another folder has to mention the function's file (an import, a type) to call it.
            // A common name needs that even in the same folder.
            if !knowsFunction && (!sameFolder || Self.genericNames.contains(function.name)) { continue }
            var score = 0
            if knowsFunction { score += 3 }
            if sameFolder { score += 1 }
            if changedLines[call.path] != nil { score += 2 }
            if changedLines[call.path]?.contains(line) == true { score += 2 }
            if let current = best, current.score > score || (current.score == score && (current.caller.path, current.line) <= (caller.path, line)) {
                continue
            }
            best = (caller, line, score)
        }
        return best.map { (function: $0.caller, line: $0.line) }
    }

    /// The function's file name, plus the names of interfaces or parents it seems to implement: other
    /// definitions of the same name in files this file mentions. Callers often go through those.
    private func typeNames(for function: SymbolLocation) -> [String] {
        var names = Self.moduleNames(of: function.path)
        let family = Self.languageFamily(of: function.path)
        for other in candidateDefinitions(named: function.name, family: family) where other.path != function.path {
            let name = Self.baseName(other.path)
            if mentions(function.path, name) { names.append(name) }
        }
        return names
    }

    // MARK: - Going down

    /// The most relevant function called inside another, and the line of the call.
    func bestCallee(inside function: SymbolLocation, preferring selection: ClosedRange<Int>?,
                    visited: Set<String>) -> (function: SymbolLocation, line: Int)? {
        var best: (callee: SymbolLocation, line: Int, score: Int)?
        var checked = Set<String>()
        for call in index.calls(inside: function.lines, of: function.path) where call.name != function.name {
            let line = call.lines.lowerBound
            let isSelected = selection?.contains(line) == true
            // Each name is looked up once, except that a call on the selected lines can still win.
            guard !checked.contains(call.name) || isSelected else { continue }
            checked.insert(call.name)
            guard let callee = bestDefinition(named: call.name, calledFrom: function.path),
                  !visited.contains(Self.key(callee)), !isTrivial(callee) else { continue }
            var score = 0
            if isSelected { score += 6 }
            if changedLines[function.path]?.contains(line) == true { score += 2 }
            if let changed = changedLines[callee.path] {
                score += 1
                if callee.lines.contains(where: changed.contains) { score += 3 }
            }
            // A function with a real body says more about the path than a small helper.
            if callee.lines.count >= 8 { score += 1 }
            // On a tie, the earlier call wins: that's the order the code runs in.
            if let current = best, current.score >= score { continue }
            best = (callee, line, score)
        }
        return best.map { (function: $0.callee, line: $0.line) }
    }

    /// The definition a call by this name, from this file, most likely means. nil when no definition is
    /// believable: none in the same language, or several with nothing to choose between them.
    func bestDefinition(named name: String, calledFrom path: String) -> SymbolLocation? {
        let family = Self.languageFamily(of: path)
        let candidates = candidateDefinitions(named: name, family: family)
        guard !candidates.isEmpty else { return nil }
        var best: (definition: SymbolLocation, score: Int)?
        for definition in candidates {
            let sameFile = definition.path == path
            if !sameFile && isPrivate(definition) { continue }
            let mentioned = !sameFile && Self.moduleNames(of: definition.path).contains { mentions(path, $0) }
            let sameFolder = Self.folder(definition.path) == Self.folder(path)
            // Calling code in another folder means importing or naming it, so the calling file mentions it.
            // A common name needs that even in the same folder, since it's most likely a library call.
            if !sameFile && !mentioned && (!sameFolder || Self.genericNames.contains(name)) { continue }
            var score = 0
            if sameFile { score += 4 }
            if mentioned { score += 3 }
            if sameFolder { score += 1 }
            if changedLines[definition.path] != nil { score += 1 }
            if isAbstract(definition) { score -= 3 }
            if let current = best, current.score >= score { continue }
            best = (definition, score)
        }
        guard let chosen = best?.definition else { return nil }
        // An interface method has no body to show; follow it to a class that implements it, if there's one.
        if isAbstract(chosen) {
            let interface = Self.baseName(chosen.path)
            if let implementation = candidates.first(where: { !isAbstract($0) && mentions($0.path, interface) }) {
                return implementation
            }
        }
        return chosen
    }

    private func candidateDefinitions(named name: String, family: String?) -> [SymbolLocation] {
        index.definitions(named: name).filter { $0.isCallable && Self.languageFamily(of: $0.path) == family && !isExcluded($0.path) }
    }

    // MARK: - What to leave out

    /// Getters, setters and one-line wrappers, which say nothing about the path.
    func isTrivial(_ function: SymbolLocation) -> Bool {
        let name = function.name
        for prefix in ["get", "set", "is", "has", "with"] where name.hasPrefix(prefix) {
            let rest = name.dropFirst(prefix.count)
            if let first = rest.first, first.isUppercase || first == "_" {
                return function.lines.count <= 5
            }
        }
        return false
    }

    /// Whether a function is private, so only its own file can call it. Looks at the lines from the
    /// start of the definition (which may be annotations) to the one with its name.
    func isPrivate(_ function: SymbolLocation) -> Bool {
        let start = function.lines.lowerBound
        let header = index.lines(start...min(function.lines.upperBound, start + 4), of: function.path) ?? []
        for line in header {
            let words = line.split { !($0.isLetter || $0.isNumber || $0 == "_") }
            if words.contains("private") || words.contains("fileprivate") { return true }
            if words.contains(Substring(function.name)) { break }
        }
        return false
    }

    /// A declaration without a body, like a method in a Java interface.
    private func isAbstract(_ function: SymbolLocation) -> Bool {
        guard function.lines.count <= 2, let last = index.lines(function.lines, of: function.path)?.last else { return false }
        return last.trimmingCharacters(in: .whitespaces).hasSuffix(";")
    }

    /// Tests, stories and generated code, which aren't the path the change takes in production.
    func isExcluded(_ path: String) -> Bool {
        Self.isTestOrGeneratedPath(path) || hasGeneratedHeader(path)
    }

    /// Generated files usually say so in their first few lines.
    private func hasGeneratedHeader(_ path: String) -> Bool {
        let header = (index.lines(0...12, of: path) ?? []).joined(separator: "\n").lowercased()
        return ["do not edit", "@generated", "generated by", "auto-generated", "autogenerated", "code generated"]
            .contains { header.contains($0) }
    }

    static func isTestOrGeneratedPath(_ path: String) -> Bool {
        let folders: Set<String> = ["test", "tests", "__tests__", "__mocks__", "mocks", "spec", "specs", "testing", "testdata",
                                    "fixtures", "androidtest", "stories", ".storybook", "storybook", "generated",
                                    "generated-sources", "jooq"]
        let components = path.lowercased().split(separator: "/").map(String.init)
        if components.dropLast().contains(where: folders.contains) { return true }
        let fileName = (path as NSString).lastPathComponent
        let lowered = fileName.lowercased()
        for marker in [".test.", ".tests.", ".spec.", "_tests.", ".stories.", ".story.", "_test.", "_spec.", ".generated.", ".pb.", "_pb2.", ".g.", ".d.ts"]
            where lowered.contains(marker) {
            return true
        }
        if lowered.hasPrefix("test_") { return true }
        let base = (fileName as NSString).deletingPathExtension
        for suffix in ["Test", "Tests", "Spec"] where base.hasSuffix(suffix) && base.count > suffix.count {
            return true
        }
        // Java integration tests, like OrderServiceIT.
        if base.hasSuffix("IT"), base.count > 2, base.dropLast(2).last?.isLowercase == true { return true }
        return false
    }

    /// Names so common that a match by name alone means nothing.
    static let genericNames: Set<String> = [
        "get", "set", "of", "from", "build", "builder", "newBuilder", "toString", "equals", "hashCode", "valueOf", "values",
        "apply", "accept", "map", "flatMap", "filter", "forEach", "stream", "collect", "add", "put", "remove", "size",
        "isEmpty", "contains", "close", "init", "onNext", "onCompleted", "onError", "then", "catch", "push", "log", "info",
        "debug", "warn", "error", "print", "println", "format", "parse", "toJSON", "render", "length", "keys", "join", "split",
    ]

    // MARK: - Helpers

    /// Whether a file mentions a word, like the name of a class or module, as a whole word.
    func mentions(_ path: String, _ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let text = index.allLines(of: path).joined(separator: "\n")
        var searchStart = text.startIndex
        while let found = text.range(of: word, range: searchStart..<text.endIndex) {
            let before = found.lowerBound == text.startIndex ? nil : text[text.index(before: found.lowerBound)]
            let after = found.upperBound == text.endIndex ? nil : text[found.upperBound]
            if !Self.isWordCharacter(before) && !Self.isWordCharacter(after) { return true }
            searchStart = found.upperBound
        }
        return false
    }

    private static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || character == "_"
    }

    /// Languages that can call each other directly. Calls are only followed within one of these.
    static func languageFamily(of path: String) -> String? {
        guard let language = SyntaxLanguage.detect(path: path) else { return nil }
        switch language {
        case .typescript, .tsx, .javascript: return "javascript"
        case .java, .kotlin, .scala: return "jvm"
        case .c, .cpp: return "c"
        default: return language.rawValue
        }
    }

    /// "OrderService" for "src/OrderService.java".
    static func baseName(_ path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// The names other files use to reach a file's code: its name, and for Go, its package's folder.
    static func moduleNames(of path: String) -> [String] {
        var names = [baseName(path)]
        if SyntaxLanguage.detect(path: path) == .go {
            names.append((folder(path) as NSString).lastPathComponent)
        }
        return names
    }

    static func folder(_ path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    static func key(_ function: SymbolLocation) -> String {
        "\(function.path):\(function.lines.lowerBound)"
    }
}
