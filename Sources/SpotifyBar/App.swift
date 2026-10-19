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

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        statusItem = StatusItemController(model: model)
        statusItem.onSignOut = { [unowned self] in model.signOut() }
        hoverCard = HoverCardController(model: model, anchor: { [unowned self] in (statusItem.buttonFrameInScreen, statusItem.screen) },
                                        onOpenSettings: {})
        statusItem.onHoverChanged = { [unowned self] inside in hoverCard.itemHover(inside) }
    }
}
