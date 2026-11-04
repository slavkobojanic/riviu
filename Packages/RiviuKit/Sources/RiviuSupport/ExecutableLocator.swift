import Foundation

/// Finds command-line tools the way the user's Terminal would.
///
/// Apps launched from Finder don't inherit the shell's `PATH`, so tools installed with Homebrew, npm or
/// installers in `~/.local/bin` aren't visible. We ask the login shell for its `PATH` once and reuse it.
public enum ExecutableLocator {
    public static let searchPath: String = {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellPath = runAndRead(shell, arguments: ["-l", "-c", "printf %s \"$PATH\""]) ?? ""
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fallbacks = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        return ([shellPath] + fallbacks).filter { !$0.isEmpty }.joined(separator: ":")
    }()

    /// API keys people export in their shell profile (often `.zshrc`, which only interactive shells read).
    /// Apps opened from the Dock don't get them, so they're read from the shell once.
    private static let shellKeyNames = ["OPENROUTER_API_KEY"]

    private static let shellKeys: [String: String] = {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var keys: [String: String] = [:]
        for name in shellKeyNames where ProcessInfo.processInfo.environment[name] == nil {
            // Markers around the value, since an interactive shell may print other things as it starts.
            guard let output = runAndRead(shell, arguments: ["-l", "-i", "-c", "printf '<<riviu>>%s<</riviu>>' \"$\(name)\""]),
                  let start = output.range(of: "<<riviu>>"), let end = output.range(of: "<</riviu>>"),
                  start.upperBound <= end.lowerBound else { continue }
            let value = String(output[start.upperBound..<end.lowerBound])
            if !value.isEmpty { keys[name] = value }
        }
        return keys
    }()

    /// The environment child processes run with: ours, plus the login shell's `PATH`
    /// (Codex, for example, is a Node script and needs `node` on the path) and API keys from the shell profile.
    public static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath
        environment.merge(shellKeys) { ours, _ in ours }
        return environment
    }

    public static func find(_ name: String) -> URL? {
        for directory in searchPath.split(separator: ":") {
            let candidate = URL(filePath: String(directory)).appending(path: name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func runAndRead(_ executable: String, arguments: [String]) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
