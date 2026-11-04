import AppKit
import RiviuAI
import RiviuSupport
import SwiftUI

struct AISettingsTab: View {
    @Bindable var settings: AppSettings
    let rules: ReviewRuleStore
    /// OpenRouter is offered once Pi says it can reach it.
    @State private var isOpenRouterReady = false

    var body: some View {
        Form {
            ForEach(AITask.allCases) { task in
                TaskSection(task: task, settings: settings, isOpenRouterReady: isOpenRouterReady)
            }
            ReviewRulesSection(rules: rules, settings: settings)
            Section {
                ForEach(CommandLineTool.allCases, id: \.self) { tool in
                    CommandLineToolRow(tool: tool, settings: settings)
                }
            } header: {
                Text("Command-line tools")
            } footer: {
                Text("Claude Code, Codex and Cursor use the account you're signed into in their CLI, including your subscription. "
                     + "Pi runs OpenRouter models, with Pi's OpenRouter sign-in or OPENROUTER_API_KEY"
                     + (isOpenRouterReady ? " (found)." : " (not found yet)."))
                    .font(.caption)
            }
            AnthropicAPISection()
        }
        .formStyle(.grouped)
        .task { isOpenRouterReady = await AISetup.isOpenRouterReady(settings: settings) }
    }
}

/// Which provider and model a task uses, and the instructions sent with it.
private struct TaskSection: View {
    let task: AITask
    @Bindable var settings: AppSettings
    let isOpenRouterReady: Bool

    var body: some View {
        Section(task.title) {
            Picker("Provider", selection: provider) {
                ForEach(providers) { Text($0.title).tag($0) }
            }
            ModelField(model: model, suggestions: settings.provider(for: task).suggestedModels, placeholder: modelPlaceholder)
            if task == .explain {
                Picker("Length", selection: $settings.explanationLength) {
                    ForEach(ExplanationLength.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            InstructionsEditor(task: task, settings: settings)
            ConnectionTestRow(task: task, settings: settings)
        }
    }

    /// OpenRouter only once it's ready, unless this task already uses it.
    private var providers: [AIProviderKind] {
        AIProviderKind.allCases.filter { $0 != .openRouter || isOpenRouterReady || settings.provider(for: task) == .openRouter }
    }

    private var modelPlaceholder: String {
        switch settings.provider(for: task) {
        case .anthropicAPI: AnthropicAPIProvider.defaultModel
        case .openRouter: "OpenRouter model ID, like ~anthropic/claude-sonnet-latest"
        default: "Default for your account"
        }
    }

    private var provider: Binding<AIProviderKind> {
        Binding(get: { settings.provider(for: task) }, set: { newValue in
            settings.setProvider(newValue, for: task)
            settings.setModel("", for: task) // model names differ between providers
        })
    }

    private var model: Binding<String> {
        Binding(get: { settings.model(for: task) }, set: { settings.setModel($0, for: task) })
    }
}

/// A model name, typed or picked from suggestions.
private struct ModelField: View {
    @Binding var model: String
    let suggestions: [String]
    let placeholder: String

    var body: some View {
        HStack {
            TextField("Model", text: $model, prompt: Text(placeholder))
            if !suggestions.isEmpty {
                Menu("Suggestions") {
                    Button("Default") { model = "" }
                    Divider()
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { model = suggestion }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }
}

private struct InstructionsEditor: View {
    let task: AITask
    let settings: AppSettings
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup("Instructions", isExpanded: $isExpanded) {
            TextEditor(text: instructions)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
            HStack {
                Text(footnote)
                    .font(.caption)
                Spacer()
                Button("Restore Default") { settings.setInstructions(defaultInstructions, for: task) }
                    .disabled(settings.instructions(for: task) == defaultInstructions)
            }
        }
    }

    private var defaultInstructions: String {
        ReviewPrompts.defaultInstructions(for: task)
    }

    private var footnote: String {
        switch task {
        case .review: "Sent before the diffs, followed by the repository's CLAUDE.md, AGENTS.md or Copilot instructions if it has them. The reply format Riviu needs is added at the end."
        case .chat: "Sent before the pull request's details and diffs."
        case .explain: "Sent before the code. The length setting is added at the end."
        }
    }

    private var instructions: Binding<String> {
        Binding(get: { settings.instructions(for: task) }, set: { settings.setInstructions($0, for: task) })
    }
}

private struct CommandLineToolRow: View {
    let tool: CommandLineTool
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(tool.displayName) {
                if let executable = AISetup.executable(for: tool, settings: settings) {
                    Label(executable.path, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.statusGreen)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Label("Not found", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.statusRed)
                }
            }
            if AISetup.executable(for: tool, settings: settings) == nil {
                Text(tool.installHint)
                    .font(.caption)
            }
            HStack {
                TextField("Path", text: customPath, prompt: Text("Find “\(tool.executableName)” automatically"))
                    .labelsHidden()
                Button("Choose…", action: chooseExecutable)
            }
        }
    }

    private var customPath: Binding<String> {
        Binding(get: { settings.customPath(for: tool) }, set: { settings.setCustomPath($0, for: tool) })
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
    @State private var apiKey = AISetup.keychain.string(for: AISetup.apiKeyAccount) ?? ""
    @State private var saveError: String?

    var body: some View {
        Section {
            SecureField("API key", text: $apiKey, prompt: Text("sk-ant-…"))
                .onChange(of: apiKey) { saveKey() }
            if let saveError {
                Text(saveError)
                    .foregroundStyle(.statusRed)
            }
        } header: {
            Text("Claude API")
        } footer: {
            Text("Only needed for tasks set to the Claude API. The key is stored in your keychain.")
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

/// Sends a tiny prompt with a task's provider and model to check they work.
private struct ConnectionTestRow: View {
    let task: AITask
    let settings: AppSettings

    private enum Result {
        case success(String)
        case failure(String)
    }

    @State private var isTesting = false
    @State private var result: Result?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Button("Test", action: test)
                .disabled(isTesting)
            if isTesting {
                ProgressView()
                    .controlSize(.small)
            }
            switch result {
            case let .success(reply):
                Label("Connected: “\(reply)”", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.statusGreen)
                    .lineLimit(2)
            case let .failure(message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.statusRed)
                    .lineLimit(4)
            case nil:
                EmptyView()
            }
        }
        .onChange(of: settings.provider(for: task)) { result = nil }
        .onChange(of: settings.model(for: task)) { result = nil }
    }

    private func test() {
        isTesting = true
        result = nil
        Task {
            do {
                let provider = try AISetup.makeProvider(for: task, settings: settings)
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
