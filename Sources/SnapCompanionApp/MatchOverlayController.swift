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
        if let frame = NSScreen.main?.visibleFrame {
            panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - 280, y: frame.maxY - 20))
        }
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
    }
}
