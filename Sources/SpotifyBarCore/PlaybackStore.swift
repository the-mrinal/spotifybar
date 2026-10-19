import Foundation
import Observation

public enum PlaybackPhase: Equatable, Sendable {
    case signedOut
    case idle
    case active(PlayerSnapshot)
}

/// What the local Spotify client last broadcast via `com.spotify.client.PlaybackStateChanged`.
public struct LocalHint: Sendable, Equatable {
    public var trackID: String?
    public var isPlaying: Bool
    public var at: Date

    public init(trackID: String?, isPlaying: Bool, at: Date) {
        self.trackID = trackID
        self.isPlaying = isPlaying
        self.at = at
    }
}

@MainActor @Observable
public final class PlaybackStore {
    public private(set) var phase: PlaybackPhase = .signedOut
    public private(set) var devices: [Device] = []
    public private(set) var lastError: String?
    public private(set) var isStale = false
    public var localHint: LocalHint?
    /// Called after every control action so the scheduler can fetch fresh state.
    @ObservationIgnored public var onAction: (() -> Void)?

    @ObservationIgnored private let api: SpotifyAPIClient
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let localSpotifyRunning: () -> Bool
    @ObservationIgnored private var lastSuccess: Date?
    @ObservationIgnored private var lastDeviceID: String?
    @ObservationIgnored private var lastErrorAt: Date?

    public init(api: SpotifyAPIClient, now: @escaping () -> Date = Date.init, localSpotifyRunning: @escaping () -> Bool) {
        self.api = api
        self.now = now
        self.localSpotifyRunning = localSpotifyRunning
    }

    public var snapshot: PlayerSnapshot? {
        if case .active(let s) = phase { return s }
        return nil
    }

    // MARK: Fetching

    public func refresh() async throws {
        do {
            let result = try await api.player()
            phase = result.map(PlaybackPhase.active) ?? .idle
            if let id = result?.device.id { lastDeviceID = id }
            lastSuccess = now()
            isStale = false
            // Control errors stay visible for a few seconds even though a fetch follows right away.
            if let at = lastErrorAt, now().timeIntervalSince(at) > 4 { lastError = nil; lastErrorAt = nil }
        } catch {
            if let lastSuccess, now().timeIntervalSince(lastSuccess) > 60 { isStale = true }
            throw error
        }
    }

    public func refreshDevices() async {
        if let list = try? await api.devices() { devices = list }
    }

    /// Leaves the signed-out phase so the scheduler polls (and backs off) until the first fetch succeeds.
    public func markSignedIn() {
        if phase == .signedOut { phase = .idle }
    }

    public func setSignedOut() {
        phase = .signedOut
        devices = []
        lastError = nil
        isStale = false
    }

    // MARK: Controls

    public func togglePlay() async {
        guard var s = snapshot else {
            await perform { try await self.api.play(deviceID: self.lastDeviceID) }
            return
        }
        let previous = phase
        s.progressMs = progressMs(at: now())
        s.fetchedAt = now()
        s.isPlaying.toggle()
        phase = .active(s)
        let playing = s.isPlaying
        await perform(revertTo: previous) {
            if playing { try await self.api.play(deviceID: nil) } else { try await self.api.pause() }
        }
    }

    public func next() async { await perform { try await self.api.next() } }
    public func previous() async { await perform { try await self.api.previous() } }

    public func setVolume(_ percent: Int) async {
        let clamped = min(100, max(0, percent))
        let previous = phase
        if var s = snapshot {
            s.device.volumePercent = clamped
            phase = .active(s)
        }
        await perform(revertTo: previous) { try await self.api.setVolume(clamped) }
    }

    public func transfer(to device: Device) async {
        await perform { try await self.api.transfer(to: device.id) }
    }

    private func perform(revertTo previous: PlaybackPhase? = nil, _ action: @escaping () async throws -> Void) async {
        do {
            try await action()
            lastError = nil
            lastErrorAt = nil
        } catch {
            if let previous { phase = previous }
            lastError = Self.message(for: error)
            lastErrorAt = now()
        }
        onAction?()
    }

    static func message(for error: Error) -> String {
        switch error as? SpotifyAPIError {
        case .notFound: "That device is no longer available"
        case .forbidden: "Spotify didn't allow that (Premium needed?)"
        case .rateLimited: "Spotify is busy, try again shortly"
        default: "Couldn't reach Spotify"
        }
    }

    // MARK: Derived

    public func progressMs(at date: Date) -> Int {
        guard let s = snapshot else { return 0 }
        guard s.isPlaying else { return min(s.progressMs, s.track.durationMs) }
        let elapsed = Int(date.timeIntervalSince(s.fetchedAt) * 1000)
        return min(s.track.durationMs, max(0, s.progressMs + elapsed))
    }

    /// The active device is this Mac only when the API, the running app, and the local broadcast all agree.
    public var isThisMac: Bool {
        guard let s = snapshot, s.device.kind == .computer, localSpotifyRunning(), let hint = localHint else { return false }
        return hint.trackID == s.track.id && hint.isPlaying == s.isPlaying
    }
}
