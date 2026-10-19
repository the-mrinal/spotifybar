import SwiftUI

@main
struct SpotifyBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var statusItem: StatusItemController!
    private var hoverCard: HoverCardController!
    private var remote: RemotePanelController!
    private var settings: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        settings = SettingsWindowController(model: model)
        statusItem = StatusItemController(model: model)
        let anchor = { [unowned self] in (statusItem.buttonFrameInScreen, statusItem.screen) }
        let openSettings = { [unowned self] in
            remote.close()
            settings.show()
        }
        hoverCard = HoverCardController(model: model, anchor: anchor, onOpenSettings: openSettings)
        remote = RemotePanelController(model: model, anchor: anchor, onOpenSettings: openSettings)

        statusItem.onHoverChanged = { [unowned self] inside in hoverCard.itemHover(inside) }
        statusItem.onClick = { [unowned self] in remote.toggle() }
        statusItem.onSettings = openSettings
        statusItem.onSignOut = { [unowned self] in model.signOut() }
        remote.onVisibilityChanged = { [unowned self] open in
            hoverCard.suppress(open)
            statusItem.setHighlighted(open)
        }

        if model.clientID.isEmpty { settings.show() }
    }
}
