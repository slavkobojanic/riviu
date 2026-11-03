// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RiviuKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RiviuDiff", targets: ["RiviuDiff"]),
        .library(name: "RiviuSyntax", targets: ["RiviuSyntax"]),
        .library(name: "RiviuSupport", targets: ["RiviuSupport"]),
        .library(name: "RiviuAI", targets: ["RiviuAI"]),
        .library(name: "RiviuGitHub", targets: ["RiviuGitHub"]),
        .library(name: "RiviuMarkdown", targets: ["RiviuMarkdown"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.10.0"),
        .package(url: "https://github.com/alex-pinkus/tree-sitter-swift", exact: "0.7.4-with-generated-files"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", from: "0.23.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-javascript", exact: "0.23.1"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-python", exact: "0.23.6"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-go", from: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-rust", from: "0.24.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-json", from: "0.24.8"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-markdown", from: "0.5.4"),
        .package(url: "https://github.com/gonzalezreal/textual", from: "0.5.0"),
    ],
    targets: [
        .target(name: "RiviuDiff"),
        .testTarget(name: "RiviuDiffTests", dependencies: ["RiviuDiff"]),
        .target(name: "RiviuSupport"),
        .target(name: "RiviuAI", dependencies: ["RiviuSupport"]),
        .target(name: "RiviuGitHub", dependencies: ["RiviuSupport"]),
        .testTarget(name: "RiviuGitHubTests", dependencies: ["RiviuGitHub"]),
        .testTarget(name: "RiviuAITests", dependencies: ["RiviuAI", "RiviuSupport"]),
        .target(
            name: "RiviuSyntax",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
                .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
                .product(name: "TreeSitterPython", package: "tree-sitter-python"),
                .product(name: "TreeSitterGo", package: "tree-sitter-go"),
                .product(name: "TreeSitterRust", package: "tree-sitter-rust"),
                .product(name: "TreeSitterJSON", package: "tree-sitter-json"),
                .product(name: "TreeSitterMarkdown", package: "tree-sitter-markdown"),
            ]
        ),
        .target(
            name: "RiviuMarkdown",
            dependencies: [.product(name: "Textual", package: "textual")]
        ),
    ]
)
