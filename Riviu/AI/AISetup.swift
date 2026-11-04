import Foundation
import RiviuAI
import RiviuSupport

/// Creates the AI provider the user picked in Settings.
enum AISetup {
    static let keychain = KeychainStore(service: "Riviu")
    static let apiKeyAccount = "anthropic-api-key"

    /// Where CLIs run. They get no tools, but they still need a directory to start in.
    static let workingDirectory = URL.applicationSupportDirectory.appending(path: "Riviu/AI Workspace", directoryHint: .isDirectory)

    static func makeProvider(for task: AITask, settings: AppSettings) throws -> AIProvider {
        let model = settings.model(for: task).trimmingCharacters(in: .whitespaces)
        if let tool = settings.provider(for: task).commandLineTool {
            guard let executable = executable(for: tool, settings: settings) else {
                throw AIProviderError.executableNotFound(tool.executableName)
            }
            return CommandLineProvider(tool: tool, executable: executable, model: model.isEmpty ? nil : model,
                                       workingDirectory: workingDirectory)
        }
        guard let apiKey = keychain.string(for: apiKeyAccount), !apiKey.isEmpty else {
            throw AIProviderError.missingAPIKey
        }
        return AnthropicAPIProvider(apiKey: apiKey, model: model.isEmpty ? AnthropicAPIProvider.defaultModel : model)
    }

    /// "Claude Code  sonnet", for showing which model is answering.
    static func description(of task: AITask, settings: AppSettings) -> String {
        let model = settings.model(for: task).trimmingCharacters(in: .whitespaces)
        let provider = settings.provider(for: task)
        if model.isEmpty {
            return provider == .anthropicAPI ? "Claude API (\(AnthropicAPIProvider.defaultModel))" : provider.title
        }
        return "\(provider == .anthropicAPI ? "Claude API" : provider.title) (\(model))"
    }

    /// The user's custom path if they set one, otherwise wherever the tool is on the PATH.
    static func executable(for tool: CommandLineTool, settings: AppSettings) -> URL? {
        let customPath = settings.customPath(for: tool).trimmingCharacters(in: .whitespaces)
        if !customPath.isEmpty {
            return FileManager.default.isExecutableFile(atPath: customPath) ? URL(filePath: customPath) : nil
        }
        return ExecutableLocator.find(tool.executableName)
    }
}
