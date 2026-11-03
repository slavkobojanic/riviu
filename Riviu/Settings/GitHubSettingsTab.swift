import RiviuGitHub
import SwiftUI

struct GitHubSettingsTab: View {
    @Bindable var settings: AppSettings
    let account: GitHubAccount

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
