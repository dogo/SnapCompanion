import AppKit
import SwiftUI

@MainActor
final class MatchOverlayController {
    private let panel: NSPanel

    init(model: AppModel) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        let host = NSHostingView(rootView: MatchOverlayView(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
    }

    func show() {
        if let frame = NSScreen.main?.visibleFrame, let host = panel.contentView {
            // Anchor by the real content width so the panel never starts partly off-screen.
            panel.setContentSize(host.fittingSize)
            panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - panel.frame.width - 20, y: frame.maxY - 20))
        }
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
    }
}

/// Background view that drags its window; isMovableByWindowBackground doesn't fire through SwiftUI content.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
