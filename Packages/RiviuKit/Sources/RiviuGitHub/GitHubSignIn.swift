import Foundation
import RiviuSupport

/// Ways to get a GitHub access token.
public enum GitHubSignIn {
    /// Scopes Riviu needs: read and review private repositories, and see organization membership.
    public static let scopes = "repo read:org"

    public enum SignInError: LocalizedError {
        case gitHubCLINotFound
        case gitHubCLINotSignedIn
        case codeExpired
        case denied
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .gitHubCLINotFound: "The GitHub CLI (gh) isn't installed."
            case .gitHubCLINotSignedIn: "The GitHub CLI isn't signed in. Run `gh auth login` in Terminal first."
            case .codeExpired: "The sign-in code expired. Start again."
            case .denied: "Sign-in was cancelled on GitHub."
            case let .failed(message): message
            }
        }
    }

    // MARK: - GitHub CLI

    public static var isGitHubCLIInstalled: Bool {
        ExecutableLocator.find("gh") != nil
    }

    /// Reuses the token the GitHub CLI (`gh`) is signed in with.
    public static func tokenFromGitHubCLI() async throws -> String {
        guard let gh = ExecutableLocator.find("gh") else { throw SignInError.gitHubCLINotFound }
        let result = try await ChildProcess.output(of: gh, arguments: ["auth", "token"])
        let token = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0, !token.isEmpty else { throw SignInError.gitHubCLINotSignedIn }
        return token
    }

    // MARK: - Device flow (needs a registered GitHub OAuth App)

    public struct DeviceCode: Decodable, Sendable {
        public let deviceCode: String
        /// The code the user types on GitHub, e.g. "WDJB-MJHT".
        public let userCode: String
        public let verificationUri: URL
        public let expiresIn: Int
        public let interval: Int
    }

    /// Step 1: ask GitHub for a code to show the user.
    public static func requestDeviceCode(clientID: String) async throws -> DeviceCode {
        let data = try await postForm(to: "https://github.com/login/device/code", fields: ["client_id": clientID, "scope": scopes])
        do {
            return try GitHubClient.decoder.decode(DeviceCode.self, from: data)
        } catch {
            throw SignInError.failed(GitHubClient.errorMessage(in: data))
        }
    }

    /// Step 2: wait while the user enters the code on GitHub, then return the token.
    public static func waitForDeviceToken(clientID: String, code: DeviceCode) async throws -> String {
        struct TokenResponse: Decodable {
            let accessToken: String?
            let error: String?
            let errorDescription: String?
        }
        var interval = code.interval
        let deadline = Date.now.addingTimeInterval(TimeInterval(code.expiresIn))

        while Date.now < deadline {
            try await Task.sleep(for: .seconds(interval))
            let data = try await postForm(to: "https://github.com/login/oauth/access_token", fields: [
                "client_id": clientID,
                "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            let response = try GitHubClient.decoder.decode(TokenResponse.self, from: data)
            if let token = response.accessToken {
                return token
            }
            switch response.error {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "expired_token": throw SignInError.codeExpired
            case "access_denied": throw SignInError.denied
            default: throw SignInError.failed(response.errorDescription ?? response.error ?? "Sign-in failed.")
            }
        }
        throw SignInError.codeExpired
    }

    private static func postForm(to address: String, fields: [String: String]) async throws -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: URL(string: address)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        return try await URLSession.shared.data(for: request).0
    }
}
