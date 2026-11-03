import AppKit
import RiviuGitHub
import SwiftUI

/// The ways to connect a GitHub account, shown in the sidebar and in Settings.
struct GitHubSignInOptions: View {
    let account: GitHubAccount
    @Environment(AppSettings.self) private var settings
    @State private var showsTokenSheet = false
    @State private var deviceCode: GitHubSignIn.DeviceCode?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if GitHubSignIn.isGitHubCLIInstalled {
                Button("Use GitHub CLI Sign-in", systemImage: "terminal") {
                    run { await account.signInWithGitHubCLI() }
                }
                .help("Reuse the account you signed into with `gh auth login`")
            }
            if !settings.gitHubClientID.isEmpty {
                Button("Sign in with GitHub…", systemImage: "globe", action: startDeviceFlow)
            }
            Button("Use a Personal Access Token…", systemImage: "key") { showsTokenSheet = true }
            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            if let error = account.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .buttonStyle(.link)
        .sheet(isPresented: $showsTokenSheet) {
            AccessTokenSheet(account: account)
        }
        .sheet(item: $deviceCode) { code in
            DeviceCodeSheet(code: code, clientID: settings.gitHubClientID, account: account)
        }
    }

    private func run(_ work: @escaping () async -> Void) {
        isWorking = true
        Task {
            await work()
            isWorking = false
        }
    }

    private func startDeviceFlow() {
        run {
            do {
                deviceCode = try await GitHubSignIn.requestDeviceCode(clientID: settings.gitHubClientID)
            } catch {
                account.errorMessage = error.localizedDescription
            }
        }
    }
}

extension GitHubSignIn.DeviceCode: @retroactive Identifiable {
    public var id: String { deviceCode }
}

private struct AccessTokenSheet: View {
    let account: GitHubAccount
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var isChecking = false

    private let newTokenURL = URL(string: "https://github.com/settings/tokens/new?scopes=repo,read:org&description=Riviu")!

    var body: some View {
        Form {
            Text("Create a classic token with the **repo** and **read:org** scopes, then paste it here.")
            Link("Create a token on GitHub", destination: newTokenURL)
            SecureField("Token", text: $token, prompt: Text("ghp_…"))
            if let error = account.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sign In") {
                    isChecking = true
                    Task {
                        await account.signIn(token: token)
                        isChecking = false
                        if account.isSignedIn { dismiss() }
                    }
                }
                .disabled(token.isEmpty || isChecking)
            }
        }
    }
}

private struct DeviceCodeSheet: View {
    let code: GitHubSignIn.DeviceCode
    let clientID: String
    let account: GitHubAccount
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Enter this code on GitHub")
                .font(.headline)
            Text(code.userCode)
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
            Button("Copy Code and Open GitHub") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code.userCode, forType: .string)
                NSWorkspace.shared.open(code.verificationUri)
            }
            .buttonStyle(.glassProminent)
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else {
                ProgressView("Waiting for GitHub…")
                    .controlSize(.small)
            }
            Button("Cancel") { dismiss() }
        }
        .padding(24)
        .frame(width: 380)
        .task {
            do {
                let token = try await GitHubSignIn.waitForDeviceToken(clientID: clientID, code: code)
                await account.signIn(token: token)
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
