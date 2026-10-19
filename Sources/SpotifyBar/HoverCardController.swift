import AppKit
import SwiftUI

/// Shows the hover card 350 ms after the pointer rests on the item; hides 250 ms after it leaves item and card.
@MainActor
final class HoverCardController {
    private let model: AppModel
    private let anchor: () -> (NSRect, NSScreen?)
    private let panel = FloatingPanel(keyable: false)
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var overItem = false
    private var overCard = false
    private var suppressed = false

    init(model: AppModel, anchor: @escaping () -> (NSRect, NSScreen?), onOpenSettings: @escaping () -> Void) {
        self.model = model
        self.anchor = anchor
        let root = HoverCardView(model: model, onOpenSettings: onOpenSettings)
            .onHover { [weak self] inside in self?.cardHover(inside) }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] _ in self?.reposition() }
        panel.setRoot(root)
    }

    func itemHover(_ inside: Bool) {
        overItem = inside
        if inside {
            hideTask?.cancel()
            guard !suppressed, !panel.isVisible else { return }
            showTask?.cancel()
            showTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                self?.show()
            }
        } else {
            showTask?.cancel()
            scheduleHide()
        }
    }

    func suppress(_ on: Bool) {
        suppressed = on
        if on { showTask?.cancel(); hide() }
    }

    private func cardHover(_ inside: Bool) {
        overCard = inside
        if inside { hideTask?.cancel() } else { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, !self.overItem, !self.overCard else { return }
            self.hide()
        }
    }

    private func show() {
        guard !suppressed, overItem else { return }
        reposition()
        panel.orderFrontRegardless()
        model.uiVisible = true
        model.refreshNow()
    }

    private func reposition() {
        let (rect, screen) = anchor()
        panel.position(under: rect, on: screen)
    }

    private func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        overCard = false
        model.uiVisible = false
    }
}
