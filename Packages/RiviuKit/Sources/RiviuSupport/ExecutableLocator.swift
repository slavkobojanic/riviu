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

    /// The environment child processes run with: ours, plus the login shell's `PATH`
    /// (Codex, for example, is a Node script and needs `node` on the path).
    public static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath
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
