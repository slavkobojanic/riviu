import RiviuDiff
import SwiftUI

struct SettingsView: View {
    let settings: AppSettings

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsTab(settings: settings)
            }
            Tab("Editor", systemImage: "textformat") {
                EditorSettingsTab(settings: settings)
            }
            Tab("AI", systemImage: "sparkles") {
                AISettingsTab(settings: settings)
            }
        }
        .frame(width: 600)
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
        }
        .formStyle(.grouped)
    }
}
