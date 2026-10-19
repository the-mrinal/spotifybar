import AppKit
import SwiftUI

/// Click surface: a key-able but non-activating panel, so the frontmost app keeps focus.
@MainActor
final class RemotePanelController {
    var onVisibilityChanged: (Bool) -> Void = { _ in }

    private let model: AppModel
    private let anchor: () -> (NSRect, NSScreen?)
    private let panel = FloatingPanel(keyable: true)
    private var outsideMonitor: Any?
    private var keyMonitor: Any?
    private var deviceRefresh: Task<Void, Never>?

    init(model: AppModel, anchor: @escaping () -> (NSRect, NSScreen?), onOpenSettings: @escaping () -> Void) {
        self.model = model
        self.anchor = anchor
        let root = RemoteView(model: model, onOpenSettings: onOpenSettings)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] _ in self?.reposition() }
        panel.setRoot(root)
    }

    var isOpen: Bool { panel.isVisible }

    func toggle() {
        isOpen ? close() : open()
    }

    func open() {
        reposition()
        panel.makeKeyAndOrderFront(nil)
        model.remoteVisible = true
        model.refreshNow()
        onVisibilityChanged(true)

        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = event.keyCode
            let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            let windowNumber = event.windowNumber
            let handled = MainActor.assumeIsolated { self?.handle(keyCode: code, plain: plain, windowNumber: windowNumber) ?? false }
            return handled ? nil : event
        }
        deviceRefresh = Task { [weak self] in
            while !Task.isCancelled {
                await self?.model.store.refreshDevices()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        outsideMonitor = nil
        keyMonitor = nil
        deviceRefresh?.cancel()
        model.remoteVisible = false
        onVisibilityChanged(false)
    }

    private func reposition() {
        let (rect, screen) = anchor()
        panel.position(under: rect, on: screen)
    }

    /// Returns true when the key was handled.
    private func handle(keyCode: UInt16, plain: Bool, windowNumber: Int) -> Bool {
        // Only bare keys aimed at the panel are shortcuts.
        guard windowNumber == panel.windowNumber, plain else { return false }
        let store = model.store
        // While another app AirPlays, transport keys would start Spotify on top of it.
        if model.airPlayOnly != nil, [49, 123, 124].contains(keyCode) { return true }
        switch keyCode {
        case 53: close()                                                       // Esc
        case 49: Task { await store.togglePlay() }                             // Space
        case 123: Task { await store.previous() }                              // ←
        case 124: Task { await store.next() }                                  // →
        case 126: adjustVolume(+10)                                            // ↑
        case 125: adjustVolume(-10)                                            // ↓
        default: return false
        }
        return true
    }

    private func adjustVolume(_ delta: Int) {
        guard model.volumeEnabled else { return }
        let target = (model.volume ?? 50) + delta
        Task { await model.setVolume(target) }
    }
}
