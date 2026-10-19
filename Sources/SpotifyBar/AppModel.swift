import AppKit
import AuthenticationServices
import Observation
import SpotifyBarCore

/// Holds the current auth so the API's token provider can reach it from any isolation domain.
final class AuthBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _auth: SpotifyAuth?
    var auth: SpotifyAuth? {
        get { lock.withLock { _auth } }
        set { lock.withLock { _auth = newValue } }
    }
}

@MainActor @Observable
final class AppModel {
    let store: PlaybackStore
    @ObservationIgnored let art = ArtworkCache(directory: ArtworkCache.defaultDirectory())
    @ObservationIgnored private(set) var scheduler: PollScheduler!
    @ObservationIgnored private let authBox = AuthBox()
    @ObservationIgnored private let observer = LocalSpotifyObserver()
    @ObservationIgnored private let tokenStore = KeychainTokenStore()
    @ObservationIgnored private var consecutiveErrors = 0
    @ObservationIgnored private var retryAfter: TimeInterval?
    @ObservationIgnored private var webAuthSession: ASWebAuthenticationSession?

    /// The hover card and remote panel report separately; polling speeds up while either is showing.
    var hoverVisible = false { didSet { visibilityChanged(oldValue || remoteVisible) } }
    var remoteVisible = false { didSet { visibilityChanged(hoverVisible || oldValue) } }
    var uiVisible: Bool { hoverVisible || remoteVisible }

    private func visibilityChanged(_ wasVisible: Bool) {
        if uiVisible != wasVisible { scheduler.contextChanged() }
    }
    var clientID: String {
        didSet {
            UserDefaults.standard.set(clientID, forKey: "clientID")
            if clientID != oldValue { configureAuth(); signOut() }
        }
    }
    private(set) var isSignedIn = false

    init() {
        clientID = UserDefaults.standard.string(forKey: "clientID") ?? ""
        let box = authBox
        let api = URLSessionSpotifyAPI(tokenProvider: {
            guard let auth = box.auth else { throw AuthError.notSignedIn }
            return try await auth.validAccessToken()
        })
        store = PlaybackStore(api: api, localSpotifyRunning: { LocalSpotifyObserver.isSpotifyRunning })
        scheduler = PollScheduler(context: { [unowned self] in pollContext() }, fetch: { [unowned self] in await poll() })
        // Spotify's /me/player lags a control change by ~0.5 s; fetching sooner would flip the optimistic UI back.
        store.onAction = { [unowned self] in scheduler.trigger(after: .milliseconds(700)) }

        observer.onHint = { [unowned self] hint in
            store.localHint = hint
            scheduler.trigger()
        }
        observer.onSuspendChanged = { [unowned self] suspended in
            if suspended { scheduler.contextChanged() } else { scheduler.trigger() }
        }
        observer.start()

        configureAuth()
        // A keychain read error (locked, access prompt denied) is not a sign-out; keep trying.
        let stored = Result { try tokenStore.load() }
        if case .success(nil) = stored { isSignedIn = false } else { isSignedIn = box.auth != nil }
        if isSignedIn {
            store.markSignedIn()
            scheduler.start()
        }
    }

    private func configureAuth() {
        authBox.auth = clientID.isEmpty ? nil : SpotifyAuth(clientID: clientID, store: tokenStore)
    }

    private func pollContext() -> PollContext {
        var remaining: Int?
        if let s = store.snapshot { remaining = s.track.durationMs - store.progressMs(at: Date()) }
        return PollContext(uiVisible: uiVisible, phase: store.phase, suspended: observer.isSuspended,
                           consecutiveErrors: consecutiveErrors, retryAfter: retryAfter, trackRemainingMs: remaining)
    }

    private func poll() async {
        do {
            try await refreshOnce()
        } catch SpotifyAPIError.unauthorized {
            do {
                try await authBox.auth?.forceRefresh()
                try await refreshOnce()
            } catch { handle(error) }
        } catch {
            handle(error)
        }
    }

    private func refreshOnce() async throws {
        try await store.refresh()
        consecutiveErrors = 0
        retryAfter = nil
    }

    private func handle(_ error: Error) {
        switch error {
        case AuthError.invalidGrant, AuthError.notSignedIn:
            signOut()
        case AuthError.keychainUnavailable:
            consecutiveErrors += 1
            retryAfter = nil
        case SpotifyAPIError.rateLimited(let after):
            consecutiveErrors += 1
            retryAfter = after
        default:
            consecutiveErrors += 1
            retryAfter = nil
        }
    }

    // MARK: Sign in / out

    func signIn() async throws {
        guard let auth = authBox.auth else { throw AuthError.notSignedIn }
        let verifier = PKCE.verifier()
        let state = UUID().uuidString
        let url = await auth.authorizeURL(verifier: verifier, state: state)
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            // AuthenticationServices calls this on a background XPC queue; @Sendable keeps it nonisolated
            // so Swift doesn't trap on a main-actor isolation check.
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme("spotifybar")) { @Sendable url, error in
                if let url { continuation.resume(returning: url) } else { continuation.resume(throwing: error ?? AuthError.notSignedIn) }
            }
            session.presentationContextProvider = PresentationAnchor.shared
            session.prefersEphemeralWebBrowserSession = false
            webAuthSession = session
            session.start()
        }
        webAuthSession = nil
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else { throw AuthError.notSignedIn }
        try await auth.exchange(code: code, verifier: verifier)
        isSignedIn = true
        consecutiveErrors = 0
        store.markSignedIn()
        scheduler.start()
    }

    func signOut() {
        scheduler?.stop()
        if let auth = authBox.auth { Task { await auth.signOut() } } else { tokenStore.clear() }
        consecutiveErrors = 0
        retryAfter = nil
        store.setSignedOut()
        isSignedIn = false
    }

    /// Asks the scheduler for a fetch now (coalesced), e.g. when a surface opens.
    func refreshNow() {
        scheduler.trigger()
    }

    func openSpotify() {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(URL(string: "https://open.spotify.com")!)
        }
    }
}

final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = PresentationAnchor()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? NSWindow() }
    }
}
