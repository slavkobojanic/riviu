import Foundation
import Observation

/// Something the AI review should or shouldn't flag in one repository, like "Don't flag force-unwraps in tests".
nonisolated struct ReviewRule: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    /// "owner/name".
    let repository: String
    let text: String
    let createdAt: Date
}

/// Why a finding was dismissed. Counted per repository, so Riviu can suggest a rule.
nonisolated enum DismissReason: String, Codable, Sendable, CaseIterable, Identifiable {
    case notAProblem, notWorthFixing, alreadyHandled, misreadTheCode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notAProblem: "Not a real problem"
        case .notWorthFixing: "Not worth fixing"
        case .alreadyHandled: "Already handled elsewhere"
        case .misreadTheCode: "The AI misread the code"
        }
    }
}

nonisolated struct Dismissal: Codable, Sendable {
    let repository: String
    let findingTitle: String
    let reason: DismissReason
    let date: Date
}

/// Rules you approved for AI reviews, and the findings you dismissed, saved to disk.
/// Rules are only ever added by you; Riviu never applies one on its own.
@Observable
final class ReviewRuleStore {
    private(set) var rules: [ReviewRule] = []
    private(set) var dismissals: [Dismissal] = []

    @ObservationIgnored private let fileURL = URL.applicationSupportDirectory.appending(path: "Riviu/review-rules.json")

    private struct SavedState: Codable {
        var rules: [ReviewRule]
        var dismissals: [Dismissal]
    }

    init() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        rules = saved.rules
        dismissals = saved.dismissals
    }

    func rules(for repository: String) -> [ReviewRule] {
        rules.filter { $0.repository == repository }
    }

    var repositoriesWithRules: [String] {
        Array(Set(rules.map(\.repository))).sorted()
    }

    func addRule(_ text: String, for repository: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !rules(for: repository).contains(where: { $0.text == text }) else { return }
        rules.append(ReviewRule(id: UUID(), repository: repository, text: text, createdAt: .now))
        save()
    }

    func removeRule(_ rule: ReviewRule) {
        rules.removeAll { $0.id == rule.id }
        save()
    }

    func recordDismissal(of finding: ReviewFinding, in repository: String, reason: DismissReason) {
        dismissals.append(Dismissal(repository: repository, findingTitle: finding.title, reason: reason, date: .now))
        // Only recent ones matter for suggestions.
        if dismissals.count > 500 { dismissals.removeFirst(dismissals.count - 500) }
        save()
    }

    func dismissals(in repository: String) -> [Dismissal] {
        dismissals.filter { $0.repository == repository }
    }

    var repositoriesWithDismissals: [String] {
        Array(Set(dismissals.map(\.repository))).sorted()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(SavedState(rules: rules, dismissals: dismissals)).write(to: fileURL, options: .atomic)
        } catch {
            print("Couldn't save review rules: \(error)")
        }
    }
}
