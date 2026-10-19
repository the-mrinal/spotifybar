import AppKit
import SwiftUI

/// Borderless, non-activating panel that sits at status-bar level. Never activates the app.
final class FloatingPanel: NSPanel {
    private let keyable: Bool

    init(keyable: Bool) {
        self.keyable = keyable
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        level = .statusBar
        isFloatingPanel = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { keyable }
    override var canBecomeMain: Bool { false }

    func setRoot<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]
        contentView = hosting
    }

    /// Places the panel 6 pt under `anchor`, centred, clamped to the screen's visible frame.
    func position(under anchor: NSRect, on screen: NSScreen?) {
        guard let hosting = contentView else { return }
        let size = hosting.fittingSize
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + 6), visible.maxX - size.width - 6)
        let y = anchor.minY - 6 - size.height
        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}
