import AppKit
import RiviuMarkdown
import SwiftUI

/// Loads the images in descriptions and comments, like `![Admin: the paid order](https://github.com/…/blob/…/a.png?raw=true)`.
/// GitHub only serves files of a private repository to a signed-in browser, so links to files in a repository are
/// fetched through the API with the account's token instead. Other images are fetched as they are.
nonisolated struct GitHubImageLoader: AttachmentLoader {
    let token: String?

    func attachment(for url: URL, text: String, environment: ColorEnvironmentValues) async throws -> GitHubImage {
        var request: URLRequest
        if let apiURL = Self.contentsURL(for: url) {
            request = URLRequest(url: apiURL)
            request.setValue("application/vnd.github.raw", forHTTPHeaderField: "Accept")
        } else {
            request = URLRequest(url: url)
        }
        // The token only ever goes to GitHub itself.
        if let token, let host = request.url?.host(), Self.tokenHosts.contains(host) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw URLError(.badServerResponse)
        }
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw URLError(.cannotDecodeContentData)
        }
        return GitHubImage(data: data, size: image.size, text: text)
    }

    private static let tokenHosts: Set<String> = ["github.com", "api.github.com", "raw.githubusercontent.com"]

    /// The API address of a file linked as `github.com/owner/repo/blob/branch/path` (or `/raw/`), or
    /// `raw.githubusercontent.com/owner/repo/branch/path`. Nil for any other link.
    static func contentsURL(for url: URL) -> URL? {
        let parts = url.pathComponents.filter { $0 != "/" }
        let owner: String, repository: String, branch: String, path: [String]
        switch url.host() {
        case "github.com":
            guard parts.count >= 5, parts[2] == "blob" || parts[2] == "raw" else { return nil }
            (owner, repository, branch, path) = (parts[0], parts[1], parts[3], Array(parts[4...]))
        case "raw.githubusercontent.com":
            guard parts.count >= 4 else { return nil }
            (owner, repository, branch, path) = (parts[0], parts[1], parts[2], Array(parts[3...]))
        default:
            return nil
        }
        var components = URLComponents(string: "https://api.github.com")!
        components.path = "/repos/\(owner)/\(repository)/contents/" + path.joined(separator: "/")
        components.queryItems = [URLQueryItem(name: "ref", value: branch)]
        return components.url
    }
}

/// An image from a description, shown at its own size or narrower. GIFs play.
nonisolated struct GitHubImage: Attachment {
    let data: Data
    let size: CGSize
    let text: String

    var description: String { text }

    @MainActor var body: some View {
        AnimatedImage(data: data)
            .accessibilityLabel(text)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, in environment: TextEnvironmentValues) -> CGSize {
        let width = min(proposal.width ?? size.width, size.width)
        return CGSize(width: width, height: width * size.height / size.width)
    }
}

/// NSImageView, because SwiftUI's Image shows only the first frame of a GIF.
private struct AnimatedImage: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(data: data)
        view.animates = true
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {}
}
