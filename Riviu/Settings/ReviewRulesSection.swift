import RiviuAI
import SwiftUI

/// The rules you approved for AI reviews, per repository, and rule suggestions from what you've dismissed.
struct ReviewRulesSection: View {
    let rules: ReviewRuleStore
    let settings: AppSettings

    var body: some View {
        Section {
            if rules.rules.isEmpty {
                Text("No rules yet. When a finding isn't useful, choose Dismiss → Don't Flag Similar Findings.")
                    .font(.callout)
            }
            ForEach(rules.repositoriesWithRules, id: \.self) { repository in
                VStack(alignment: .leading, spacing: 6) {
                    Text(repository)
                        .font(.headline)
                    ForEach(rules.rules(for: repository)) { rule in
                        HStack {
                            Text(rule.text)
                            Spacer()
                            Button("Remove", systemImage: "minus.circle") { rules.removeRule(rule) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help("Remove this rule")
                        }
                    }
                }
            }
            ForEach(rules.repositoriesWithDismissals.filter { rules.dismissals(in: $0).count >= 3 }, id: \.self) { repository in
                RuleSuggestions(repository: repository, rules: rules, settings: settings)
            }
        } header: {
            Text("Review Rules")
        } footer: {
            Text("Sent with every AI review of that repository. Riviu only suggests rules; nothing is added until you approve it.")
                .font(.caption)
        }
    }
}

/// Asks the AI for rules that would stop findings you keep dismissing.
private struct RuleSuggestions: View {
    let repository: String
    let rules: ReviewRuleStore
    let settings: AppSettings
    @State private var suggestions: [String]?
    @State private var isAsking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("You've dismissed \(rules.dismissals(in: repository).count) findings in \(repository).")
                Spacer()
                Button(isAsking ? "Thinking…" : "Suggest Rules", systemImage: "sparkles", action: ask)
                    .disabled(isAsking)
            }
            if let suggestions {
                if suggestions.isEmpty {
                    Text("No clear pattern yet.")
                        .font(.callout)
                }
                ForEach(suggestions, id: \.self) { suggestion in
                    HStack {
                        Text(suggestion)
                        Spacer()
                        Button("Add") {
                            rules.addRule(suggestion, for: repository)
                            self.suggestions?.removeAll { $0 == suggestion }
                        }
                    }
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.statusRed)
            }
        }
    }

    private func ask() {
        isAsking = true
        errorMessage = nil
        Task {
            do {
                let provider = try AISetup.makeProvider(for: .chat, settings: settings)
                let request = ReviewPrompts.ruleSuggestionRequest(repository: repository, dismissals: rules.dismissals(in: repository),
                                                                   existingRules: rules.rules(for: repository))
                let reply = try await provider.reply(to: request)
                suggestions = reply.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-•* ").union(.whitespaces)) }
                    .filter { !$0.isEmpty && $0 != "NONE" }
                    .prefix(3)
                    .map { $0 }
            } catch {
                errorMessage = error.localizedDescription
            }
            isAsking = false
        }
    }
}
