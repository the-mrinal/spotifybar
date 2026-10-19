import AppKit
import SpotifyBarCore

/// Listens to the local Spotify client's broadcast and to sleep/lock events. Never polls.
@MainActor
final class LocalSpotifyObserver {
    var onHint: (LocalHint) -> Void = { _ in }
    var onSuspendChanged: (Bool) -> Void = { _ in }

    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var systemAsleep = false
    private var screensAsleep = false
    private var locked = false

    var isSuspended: Bool { systemAsleep || screensAsleep || locked }

    func start() {
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, "com.spotify.client.PlaybackStateChanged") { [weak self] info in
            let trackID = info["Track ID"]?.split(separator: ":").last.map(String.init)
            self?.onHint(LocalHint(trackID: trackID, isPlaying: info["Player State"] == "Playing", at: Date()))
        }
        observe(distributed, "com.apple.screenIsLocked") { [weak self] _ in self?.set(\.locked, true) }
        observe(distributed, "com.apple.screenIsUnlocked") { [weak self] _ in self?.set(\.locked, false) }

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification.rawValue) { [weak self] _ in self?.set(\.systemAsleep, true) }
        observe(workspace, NSWorkspace.didWakeNotification.rawValue) { [weak self] _ in self?.set(\.systemAsleep, false) }
        observe(workspace, NSWorkspace.screensDidSleepNotification.rawValue) { [weak self] _ in self?.set(\.screensAsleep, true) }
        observe(workspace, NSWorkspace.screensDidWakeNotification.rawValue) { [weak self] _ in self?.set(\.screensAsleep, false) }
    }

    static var isSpotifyRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
    }

    private func set(_ key: ReferenceWritableKeyPath<LocalSpotifyObserver, Bool>, _ value: Bool) {
        let before = isSuspended
        self[keyPath: key] = value
        if before != isSuspended { onSuspendChanged(isSuspended) }
    }

    /// Delivers the notification's string-valued userInfo on the main actor.
    private func observe(_ center: NotificationCenter, _ name: String, _ handler: @escaping @MainActor ([String: String]) -> Void) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { note in
            var info: [String: String] = [:]
            for (key, value) in note.userInfo ?? [:] {
                if let key = key as? String, let value = value as? String { info[key] = value }
            }
            MainActor.assumeIsolated { handler(info) }
        }
        tokens.append((center, token))
    }
}
