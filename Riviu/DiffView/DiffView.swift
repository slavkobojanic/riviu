import AppKit
import RiviuDiff
import SwiftUI

/// Everything the diff view shows. SwiftUI updates the view whenever any of it changes.
struct DiffDisplay: Equatable {
    var rowsVersion: Int
    var syntaxVersion: Int
    var layout: DiffLayout
    var themeFamily: EditorThemeFamily
    var font: NSFont
    var lineSpacing: LineSpacing
    var findQuery: String
    var findStep: FindStep
    var lineToReveal: LineToReveal?
}

/// Puts the AppKit `DiffCanvasView` in a scroll view and keeps it in step with the workspace and settings.
struct DiffView: NSViewRepresentable {
    let display: DiffDisplay
    let workspace: ReviewWorkspace
    let settings: AppSettings
    let chats: ChatStore

    final class Coordinator {
        var canvas: DiffCanvasView?
        var rowsVersion = -1
        var findStep = FindStep()
        var revealedLineID: UUID?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let canvas = DiffCanvasView(frame: .zero)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.documentView = canvas
        context.coordinator.canvas = canvas
        connectCallbacks(of: canvas)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let canvas = context.coordinator.canvas else { return }
        let coordinator = context.coordinator

        canvas.setThemeFamily(display.themeFamily)
        canvas.setFont(display.font, lineSpacing: display.lineSpacing)

        if coordinator.rowsVersion != display.rowsVersion {
            coordinator.rowsVersion = display.rowsVersion
            canvas.setContent(rows: workspace.rows, layout: display.layout, filePath: workspace.selectedFilePath ?? "")
        }
        let syntax = workspace.syntax(forFileAt: workspace.selectedFilePath)
        canvas.setSyntax(base: syntax?.base, head: syntax?.head)

        canvas.setFindQuery(display.findQuery)
        if coordinator.findStep != display.findStep {
            coordinator.findStep = display.findStep
            canvas.moveToFindMatch(forward: display.findStep.forward)
        }
        if let line = display.lineToReveal, line.id != coordinator.revealedLineID {
            // Wait a moment so a newly created view has its size before scrolling.
            Task { @MainActor in
                if canvas.revealLine(line.lineIndex, on: line.side) {
                    coordinator.revealedLineID = line.id
                }
            }
        }
    }

    private func connectCallbacks(of canvas: DiffCanvasView) {
        let workspace = workspace
        let settings = settings
        let chats = chats

        canvas.onExpandSegment = { workspace.expandSegment($0) }
        canvas.onComment = { workspace.startComment(on: $0) }
        canvas.onFindStatus = { workspace.findStatus = $0 }

        canvas.makeAttachmentView = { [weak canvas] id in
            let view = NSHostingView(rootView: InlineItemView(id: id, workspace: workspace) { height in
                Task { @MainActor in canvas?.setAttachmentHeight(height, for: id) }
            })
            view.sizingOptions = []
            return view
        }

        canvas.makeHotPathPopover = { [weak canvas] target in
            workspace.prepareCodeIndex()
            return NSHostingController(rootView: HotPathPopover(target: target, workspace: workspace) { canvas?.closePopover() })
                .withPreferredContentSize()
        }

        canvas.goToDefinition = { [weak canvas] name, _ in
            workspace.prepareCodeIndex()
            if workspace.jumpToDefinition(of: name) { return nil }
            return NSHostingController(rootView: DefinitionPopover(name: name, workspace: workspace) { canvas?.closePopover() })
                .withPreferredContentSize()
        }

        canvas.makeExplainPopover = { [weak canvas] target in
            guard let pullRequest = workspace.pullRequest else { return NSViewController() }
            let popover = ExplainPopover(target: target, pullRequest: pullRequest, fileDiff: workspace.selectedFileDiff,
                                         settings: settings) {
                canvas?.closePopover()
                settings.showsChatPanel = true
                let systemPrompt = ReviewPrompts.chatSystemPrompt(instructions: settings.chatInstructions, pullRequest: pullRequest,
                                                                  openFile: workspace.selectedFile)
                chats.send(ReviewPrompts.continueInChatMessage(target: target), pullRequest: pullRequest, systemPrompt: systemPrompt)
            }
            let controller = NSHostingController(rootView: popover)
            controller.sizingOptions = [.preferredContentSize] // the popover grows as the answer streams in
            return controller
        }
    }
}

extension NSHostingController {
    /// Lets a popover resize as its SwiftUI content grows.
    func withPreferredContentSize() -> Self {
        sizingOptions = [.preferredContentSize]
        return self
    }
}
