import AppKit
import SwiftUI

/// Owns the NSStatusItem. Width follows the SwiftUI content; nothing here runs on a timer.
@MainActor
final class StatusItemController: NSObject {
    var onHoverChanged: (Bool) -> Void = { _ in }
    var onClick: () -> Void = {}
    var onSettings: () -> Void = {}
    var onSignOut: () -> Void = {}

    let barState = BarState()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var hostingView: BarHostingView!

    init(model: AppModel) {
        super.init()
        guard let button = statusItem.button else { return }
        let root = BarView(model: model, state: barState,
                           onClick: { [weak self] in self?.onClick() },
                           onWidth: { [weak self] width in self?.statusItem.length = ceil(width) + 2 })
        hostingView = BarHostingView(rootView: root)
        hostingView.frame = button.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.onHover = { [weak self] inside in
            self?.barState.hovering = inside
            self?.onHoverChanged(inside)
        }
        hostingView.onRightClick = { [weak self] in self?.showMenu() }
        button.addSubview(hostingView)
        button.setAccessibilityRole(.group)
    }

    var buttonFrameInScreen: NSRect {
        guard let button = statusItem.button, let window = button.window else { return .zero }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    var screen: NSScreen? { statusItem.button?.window?.screen }

    func setHighlighted(_ on: Bool) { barState.highlighted = on }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Sign Out", action: #selector(signOut), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit SpotifyBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func settings() { onSettings() }
    @objc private func signOut() { onSignOut() }
}

final class BarHostingView: NSHostingView<BarView> {
    var onHover: (Bool) -> Void = { _ in }
    var onRightClick: () -> Void = {}
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
    override func rightMouseDown(with event: NSEvent) { onRightClick() }
}
