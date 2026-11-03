import Foundation

/// A running command whose output is read line by line.
///
/// `Process` isn't Sendable, so this class owns it and only exposes thread-safe operations.
final class ChildProcess: @unchecked Sendable {
    struct ExitResult {
        let status: Int32
        let errorOutput: String
    }

    private let process = Process()
    private let output = Pipe()
    private let errors = Pipe()
    /// Standard error is read from the start: if nobody reads it, a chatty tool fills the pipe and stalls.
    private var errorOutput: Task<Data, Never>?

    init(executable: URL, arguments: [String], workingDirectory: URL) {
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = ExecutableLocator.environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
    }

    func start() throws {
        try FileManager.default.createDirectory(at: process.currentDirectoryURL!, withIntermediateDirectories: true)
        try process.run()
        let errorHandle = errors.fileHandleForReading
        errorOutput = Task.detached { errorHandle.readDataToEndOfFile() }
    }

    func stop() {
        if process.isRunning {
            process.terminate()
        }
    }

    /// Standard output split into lines, including empty ones (they matter in Markdown).
    func outputLines() -> AsyncThrowingStream<String, Error> {
        let handle = output.fileHandleForReading
        return AsyncThrowingStream { continuation in
            let task = Task {
                var buffer = Data()
                do {
                    for try await byte in handle.bytes {
                        if byte == UInt8(ascii: "\n") {
                            continuation.yield(String(decoding: buffer, as: UTF8.self))
                            buffer.removeAll(keepingCapacity: true)
                        } else {
                            buffer.append(byte)
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(String(decoding: buffer, as: UTF8.self))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func waitForExit() async -> ExitResult {
        let errorData = await errorOutput?.value ?? Data()
        let process = self.process
        await Task.detached { process.waitUntilExit() }.value
        return ExitResult(status: process.terminationStatus, errorOutput: String(decoding: errorData, as: UTF8.self))
    }
}
