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

        canvas.makeExplainPopover = { [weak canvas] target in
            let request = ReviewPrompts.explainRequest(target: target, pullRequest: workspace.pullRequest)
            let popover = ExplainPopover(target: target, request: request, makeProvider: { try AISetup.makeProvider(settings: settings) }) {
                canvas?.closePopover()
                settings.showsChatPanel = true
                chats.send(ReviewPrompts.continueInChatMessage(target: target), pullRequest: workspace.pullRequest,
                           systemPrompt: ReviewPrompts.chatSystemPrompt(pullRequest: workspace.pullRequest, openFile: workspace.selectedFile))
            }
            return NSHostingController(rootView: popover)
        }
    }
}
