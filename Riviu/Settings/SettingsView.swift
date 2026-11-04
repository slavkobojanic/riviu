import RiviuDiff
import SwiftUI

struct SettingsView: View {
    let settings: AppSettings
    let account: GitHubAccount
    let watcher: ReviewRequestWatcher
    let rules: ReviewRuleStore

    #if DEBUG
    @State private var tab = UserDefaults.standard.string(forKey: "debugSettings") ?? "General"
    #else
    @State private var tab = "General"
    #endif

    var body: some View {
        TabView(selection: $tab) {
            Tab("General", systemImage: "gearshape", value: "General") {
                GeneralSettingsTab(settings: settings)
            }
            Tab("Editor", systemImage: "textformat", value: "Editor") {
                EditorSettingsTab(settings: settings)
            }
            Tab("AI", systemImage: "sparkles", value: "AI") {
                AISettingsTab(settings: settings, rules: rules)
            }
            Tab("GitHub", systemImage: "person.crop.circle", value: "GitHub") {
                GitHubSettingsTab(settings: settings, account: account, watcher: watcher)
            }
        }
        .frame(width: 640, height: 640)
    }
}

private struct GeneralSettingsTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
            }
            Picker("Diff layout", selection: $settings.diffLayout) {
                Text("Split").tag(DiffLayout.split)
                Text("Unified").tag(DiffLayout.unified)
            }
            Stepper("Context lines around changes: \(settings.contextLines)", value: $settings.contextLines, in: 0...20)
            Toggle("Highlight changed words within lines", isOn: $settings.highlightsWordChanges)
            Toggle("Show AI chat panel", isOn: $settings.showsChatPanel)
            Toggle("Keep running in the menu bar when the window is closed", isOn: $settings.keepsRunningInMenuBar)
        }
        .formStyle(.grouped)
    }
}
