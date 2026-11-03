import RiviuGitHub
import SwiftUI

struct GitHubSettingsTab: View {
    @Bindable var settings: AppSettings
    let account: GitHubAccount
    let watcher: ReviewRequestWatcher

    var body: some View {
        Form {
            Section("Account") {
                switch account.status {
                case .checking:
                    ProgressView("Checking…")
                        .controlSize(.small)
                case .signedOut:
                    GitHubSignInOptions(account: account)
                case let .signedIn(user):
                    LabeledContent("Signed in as") {
                        HStack {
                            AsyncImage(url: user.avatarUrl) { image in
                                image.resizable()
                            } placeholder: {
                                Image(systemName: "person.crop.circle")
                            }
                            .frame(width: 20, height: 20)
                            .clipShape(.circle)
                            Text(user.name.map { "\($0) (\(user.login))" } ?? user.login)
                        }
                    }
                    Button("Sign Out", role: .destructive) { account.signOut() }
                }
            }
            ReviewRequestsSection(settings: settings, watcher: watcher)
            Section {
                TextField("OAuth App client ID", text: $settings.gitHubClientID, prompt: Text("Optional"))
            } header: {
                Text("Browser sign-in")
            } footer: {
                Text("To sign in through the browser, register a GitHub OAuth App with device flow enabled and paste its client ID here.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}

/// How often to look for new review requests, and what to do when one arrives.
private struct ReviewRequestsSection: View {
    @Bindable var settings: AppSettings
    let watcher: ReviewRequestWatcher
    @State private var isChecking = false

    var body: some View {
        Section {
            Toggle("Check for new review requests", isOn: $settings.checksForReviewRequests)
            Group {
                Picker("Check every", selection: $settings.reviewRequestCheckMinutes) {
                    ForEach([1, 5, 15, 30], id: \.self) { minutes in
                        Text(minutes == 1 ? "minute" : "\(minutes) minutes").tag(minutes)
                    }
                }
                Toggle("Show a notification", isOn: $settings.notifiesAboutReviewRequests)
                Toggle("Run an AI review automatically", isOn: $settings.reviewsNewRequestsWithAI)
                HStack {
                    status
                    Spacer()
                    Button("Check Now", action: checkNow)
                        .disabled(isChecking)
                }
            }
            .disabled(!settings.checksForReviewRequests)
        } header: {
            Text("Review requests")
        } footer: {
            Text("Riviu checks while it's open. The AI review uses the provider and model set for AI Review in the AI tab.")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var status: some View {
        if isChecking {
            ProgressView()
                .controlSize(.small)
        } else if let errorMessage = watcher.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(2)
        } else if let lastChecked = watcher.lastChecked {
            Text("Last checked \(lastChecked, format: .relative(presentation: .named))")
        } else {
            Text("Not checked yet")
        }
    }

    private func checkNow() {
        isChecking = true
        Task {
            await watcher.checkNow()
            isChecking = false
        }
    }
}
