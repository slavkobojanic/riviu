import AppKit
import RiviuAI
import SwiftUI

struct AISettingsTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $settings.aiProvider) {
                    ForEach(AIProviderKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text("Claude Code, Codex and Cursor use the account you're signed into in their CLI, including your subscription. The Claude API uses an API key and is billed per token.")
                    .font(.caption)
            }

            if let tool = settings.aiProvider.commandLineTool {
                CommandLineToolSection(tool: tool, settings: settings)
            } else {
                AnthropicAPISection(settings: settings)
            }

            Section {
                ConnectionTestRow(settings: settings)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CommandLineToolSection: View {
    let tool: CommandLineTool
    let settings: AppSettings

    var body: some View {
        Section(tool.displayName) {
            LabeledContent("Status") {
                if let executable = AISetup.executable(for: tool, settings: settings) {
                    Label(executable.path, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .textSelection(.enabled)
                } else {
                    Label("Not found", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            if AISetup.executable(for: tool, settings: settings) == nil {
                Text(tool.installHint)
                    .font(.caption)
            }

            HStack {
                TextField("Path", text: customPath, prompt: Text("Find “\(tool.executableName)” automatically"))
                Button("Choose…", action: chooseExecutable)
            }
            TextField("Model", text: model, prompt: Text("Default for your account"))
        }
    }

    private var customPath: Binding<String> {
        Binding(get: { settings.customPath(for: tool) }, set: { settings.setCustomPath($0, for: tool) })
    }

    private var model: Binding<String> {
        Binding(get: { settings.model(for: tool) }, set: { settings.setModel($0, for: tool) })
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the \(tool.executableName) executable"
        if panel.runModal() == .OK, let url = panel.url {
            settings.setCustomPath(url.path, for: tool)
        }
    }
}

private struct AnthropicAPISection: View {
    @Bindable var settings: AppSettings
    @State private var apiKey = AISetup.keychain.string(for: AISetup.apiKeyAccount) ?? ""
    @State private var saveError: String?

    var body: some View {
        Section("Claude API") {
            SecureField("API key", text: $apiKey, prompt: Text("sk-ant-…"))
                .onSubmit(saveKey)
                .onChange(of: apiKey) { saveKey() }
            if let saveError {
                Text(saveError)
                    .foregroundStyle(.red)
            }
            Picker("Model", selection: $settings.anthropicModel) {
                ForEach(AnthropicAPIProvider.models, id: \.self) { Text($0).tag($0) }
            }
            Text("The key is stored in your keychain.")
                .font(.caption)
        }
    }

    private func saveKey() {
        do {
            try AISetup.keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: AISetup.apiKeyAccount)
            saveError = nil
        } catch {
            saveError = "Couldn't save the key: \(error.localizedDescription)"
        }
    }
}

/// Sends a tiny prompt to the selected provider to check it's set up.
private struct ConnectionTestRow: View {
    let settings: AppSettings

    private enum Result {
        case success(String)
        case failure(String)
    }

    @State private var isTesting = false
    @State private var result: Result?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Button("Test Connection", action: test)
                .disabled(isTesting)
            if isTesting {
                ProgressView()
                    .controlSize(.small)
            }
            switch result {
            case let .success(reply):
                Label("Connected: “\(reply)”", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .lineLimit(2)
            case let .failure(message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(4)
            case nil:
                EmptyView()
            }
        }
        .onChange(of: settings.aiProvider) { result = nil }
    }

    private func test() {
        isTesting = true
        result = nil
        Task {
            do {
                let provider = try AISetup.makeProvider(settings: settings)
                let request = AIRequest(system: "You are a connection test.", messages: [AIMessage(role: .user, text: "Reply with the single word OK.")])
                let reply = try await provider.reply(to: request)
                result = .success(reply.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                result = .failure(error.localizedDescription)
            }
            isTesting = false
        }
    }
}
