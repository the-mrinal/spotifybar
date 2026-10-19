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

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        statusItem = StatusItemController(model: model)
        statusItem.onSignOut = { [unowned self] in model.signOut() }
    }
}
