import AppKit
import RiviuDiff
import SwiftUI

struct SettingsView: View {
    let settings: AppSettings
    let account: GitHubAccount
    let watcher: ReviewRequestWatcher
    let rules: ReviewRuleStore

    /// The tab you had open last time.
    @AppStorage("settingsTab") private var tab = "General"

    var body: some View {
        TabView(selection: $tab) {
            Tab("General", systemImage: "gearshape", value: "General") {
                GeneralSettingsTab(settings: settings)
                    .opensWithNothingFocused()
            }
            Tab("Editor", systemImage: "textformat", value: "Editor") {
                EditorSettingsTab(settings: settings)
                    .opensWithNothingFocused()
            }
            Tab("AI", systemImage: "sparkles", value: "AI") {
                AISettingsTab(settings: settings, rules: rules)
                    .frame(maxHeight: 640) // long, so it scrolls past this
                    .opensWithNothingFocused()
            }
            Tab("GitHub", systemImage: "person.crop.circle", value: "GitHub") {
                GitHubSettingsTab(settings: settings, account: account, watcher: watcher)
                    .opensWithNothingFocused()
            }
        }
        // Each tab is as tall as its content.
        .frame(width: 640)
        #if DEBUG
        .onAppear {
            if let debugTab = UserDefaults.standard.string(forKey: "debugSettings") { tab = debugTab }
        }
        #endif
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
            NumberStepperField(title: "Context lines around changes", value: $settings.contextLines, range: 0...20)
            Toggle("Highlight changed words within lines", isOn: $settings.highlightsWordChanges)
            Toggle("Show AI chat panel", isOn: $settings.showsChatPanel)
            Toggle("Keep running in the menu bar when the window is closed", isOn: $settings.keepsRunningInMenuBar)
        }
        .formStyle(.grouped)
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// A number you can type or step up and down, like the ones in System Settings.
struct NumberStepperField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    /// Shown after the number, like "pt".
    var unit: String?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: clampedValue, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                if let unit {
                    Text(unit)
                        .foregroundStyle(.secondary)
                }
                Stepper(title, value: $value, in: range)
                    .labelsHidden()
            }
        }
    }

    /// Keeps a typed number inside the range.
    private var clampedValue: Binding<Int> {
        Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) })
    }
}

extension View {
    /// Stops a Settings tab from putting the cursor in its first text field when it opens, which would show that
    /// field's text selected. Clicking a field still focuses it.
    func opensWithNothingFocused() -> some View {
        background(NothingFocusedOnOpen())
    }
}

/// An empty view that clears the window's focus once its tab has been put in the window.
private struct NothingFocusedOnOpen: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { FocusClearingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class FocusClearingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Wait a moment, so this runs after AppKit has picked the first text field.
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window, window.firstResponder is NSTextView else { return }
                window.makeFirstResponder(nil)
            }
        }
    }
}
