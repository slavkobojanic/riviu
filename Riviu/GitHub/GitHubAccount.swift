import Foundation
import Observation
import RiviuGitHub
import RiviuSupport

/// The signed-in GitHub account. The token is kept in the keychain.
@Observable
final class GitHubAccount {
    enum Status {
        case checking
        case signedOut
        case signedIn(GitHubUser)
    }

    private(set) var status: Status = .checking
    private(set) var client: GitHubClient?
    /// The most recent sign-in problem, shown next to the sign-in buttons.
    var errorMessage: String?

    @ObservationIgnored private let keychain = KeychainStore(service: "Riviu")
    @ObservationIgnored private let tokenAccount = "github-token"

    init() {
        if let token = keychain.string(for: tokenAccount) {
            Task { await signIn(token: token) }
        } else {
            status = .signedOut
        }
    }

    var user: GitHubUser? {
        if case let .signedIn(user) = status { return user }
        return nil
    }

    var isSignedIn: Bool { user != nil }

    var loader: PullRequestLoader {
        PullRequestLoader(client: client)
    }

    /// Checks the token with GitHub, then saves it.
    func signIn(token: String) async {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = GitHubClient(token: token)
        status = .checking
        do {
            let user = try await candidate.currentUser()
            try keychain.set(token, for: tokenAccount)
            client = candidate
            status = .signedIn(user)
            errorMessage = nil
        } catch {
            client = nil
            status = .signedOut
            errorMessage = error.localizedDescription
        }
    }

    func signInWithGitHubCLI() async {
        do {
            await signIn(token: try await GitHubSignIn.tokenFromGitHubCLI())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        try? keychain.set(nil, for: tokenAccount)
        client = nil
        status = .signedOut
    }
}
