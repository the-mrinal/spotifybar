import Foundation
import Testing
@testable import SpotifyBarCore

actor MockAPI: SpotifyAPIClient {
    var calls: [String] = []
    var playerResult: Result<PlayerSnapshot?, SpotifyAPIError> = .success(nil)
    var controlError: SpotifyAPIError?
    var devicesResult: [Device] = []
    private var gate: CheckedContinuation<Void, Never>?
    var gated = false

    func setPlayer(_ r: Result<PlayerSnapshot?, SpotifyAPIError>) { playerResult = r }
    func setControlError(_ e: SpotifyAPIError?) { controlError = e }
    func setGated(_ g: Bool) { gated = g }
    func release() { gate?.resume(); gate = nil }

    private func control(_ name: String) async throws {
        calls.append(name)
        if gated { await withCheckedContinuation { gate = $0 } }
        if let controlError { throw controlError }
    }

    func player() async throws -> PlayerSnapshot? { calls.append("player"); return try playerResult.get() }
    func devices() async throws -> [Device] { calls.append("devices"); return devicesResult }
    func play(deviceID: String?) async throws { try await control("play:\(deviceID ?? "-")") }
    func pause() async throws { try await control("pause") }
    func next() async throws { try await control("next") }
    func previous() async throws { try await control("previous") }
    func setVolume(_ percent: Int) async throws { try await control("volume:\(percent)") }
    func transfer(to deviceID: String) async throws { try await control("transfer:\(deviceID)") }
}

final class Clock_: @unchecked Sendable { var now = Date(timeIntervalSince1970: 3_000_000) }

func snapshot(playing: Bool = true, progress: Int = 10_000, kind: DeviceKind = .speaker, at: Date, trackID: String = "t1", volume: Int? = 50) -> PlayerSnapshot {
    PlayerSnapshot(
        track: Track(id: trackID, title: "Song", artist: "Artist", album: "Album", durationMs: 200_000, artSmall: nil, artMedium: nil, isAd: false),
        device: Device(id: "d1", name: "Kitchen", kind: kind, isActive: true, volumePercent: volume, supportsVolume: volume != nil),
        isPlaying: playing, progressMs: progress, fetchedAt: at)
}

@MainActor @Suite struct PlaybackStoreTests {
    let clock = Clock_()
    let api = MockAPI()
    var localRunning = true

    func makeStore() -> PlaybackStore {
        PlaybackStore(api: api, now: { [clock] in clock.now }, localSpotifyRunning: { [localRunning] in localRunning })
    }

    @Test func startsSignedOutUntilFirstRefresh() {
        #expect(makeStore().phase == .signedOut)
    }

    @Test func refreshSetsActive() async throws {
        let s = snapshot(at: clock.now)
        await api.setPlayer(.success(s))
        let store = makeStore()
        try await store.refresh()
        #expect(store.phase == .active(s))
        #expect(store.lastError == nil)
    }

    @Test func refresh204SetsIdle() async throws {
        let store = makeStore()
        try await store.refresh()
        #expect(store.phase == .idle)
    }

    @Test func optimisticToggleFlipsImmediately() async throws {
        await api.setPlayer(.success(snapshot(playing: true, at: clock.now)))
        let store = makeStore()
        try await store.refresh()
        await api.setGated(true)
        let task = Task { await store.togglePlay() }
        while await !api.calls.contains("pause") { await Task.yield() }
        guard case .active(let s) = store.phase else { Issue.record("not active"); return }
        #expect(s.isPlaying == false)
        await api.release()
        await task.value
    }

    @Test func revertsOptimisticToggleOnFailure() async throws {
        await api.setPlayer(.success(snapshot(playing: true, at: clock.now)))
        let store = makeStore()
        try await store.refresh()
        await api.setControlError(.notFound)
        await store.togglePlay()
        guard case .active(let s) = store.phase else { Issue.record("not active"); return }
        #expect(s.isPlaying == true)
        #expect(store.lastError != nil)
    }

    @Test func markSignedInLeavesSignedOutPhase() {
        let store = makeStore()
        store.markSignedIn()
        #expect(store.phase == .idle)
    }

    @Test func controlErrorSurvivesImmediateRefresh() async throws {
        await api.setPlayer(.success(snapshot(playing: true, at: clock.now)))
        let store = makeStore()
        try await store.refresh()
        await api.setControlError(.notFound)
        await store.togglePlay()
        try await store.refresh()
        #expect(store.lastError != nil)
        clock.now = clock.now.addingTimeInterval(5)
        try await store.refresh()
        #expect(store.lastError == nil)
    }

    @Test func playWhenIdleTargetsLastDevice() async throws {
        await api.setPlayer(.success(snapshot(playing: false, at: clock.now)))
        let store = makeStore()
        try await store.refresh()
        await api.setPlayer(.success(nil))
        try await store.refresh()
        await store.togglePlay()
        #expect(await api.calls.contains("play:d1"))
    }

    @Test func optimisticVolumeAndRevert() async throws {
        await api.setPlayer(.success(snapshot(at: clock.now, volume: 50)))
        let store = makeStore()
        try await store.refresh()
        await store.setVolume(70)
        guard case .active(let a) = store.phase else { Issue.record("not active"); return }
        #expect(a.device.volumePercent == 70)
        #expect(await api.calls.contains("volume:70"))
        await api.setControlError(.forbidden)
        await store.setVolume(90)
        guard case .active(let b) = store.phase else { Issue.record("not active"); return }
        #expect(b.device.volumePercent == 70)
    }

    @Test func interpolatesProgress() async throws {
        let t0 = clock.now
        await api.setPlayer(.success(snapshot(playing: true, progress: 10_000, at: t0)))
        let store = makeStore()
        try await store.refresh()
        #expect(store.progressMs(at: t0.addingTimeInterval(3)) == 13_000)
        #expect(store.progressMs(at: t0.addingTimeInterval(1_000)) == 200_000)
        await api.setPlayer(.success(snapshot(playing: false, progress: 10_000, at: t0)))
        try await store.refresh()
        #expect(store.progressMs(at: t0.addingTimeInterval(3)) == 10_000)
    }

    @Test func isThisMacRequiresAllThree() async throws {
        await api.setPlayer(.success(snapshot(playing: true, kind: .computer, at: clock.now, trackID: "t1")))
        var store = makeStore()
        try await store.refresh()
        store.localHint = LocalHint(trackID: "t1", isPlaying: true, at: clock.now)
        #expect(store.isThisMac)

        store.localHint = LocalHint(trackID: "other", isPlaying: true, at: clock.now)
        #expect(!store.isThisMac)
        store.localHint = LocalHint(trackID: "t1", isPlaying: false, at: clock.now)
        #expect(!store.isThisMac)

        var notRunning = self
        notRunning.localRunning = false
        store = notRunning.makeStore()
        try await store.refresh()
        store.localHint = LocalHint(trackID: "t1", isPlaying: true, at: clock.now)
        #expect(!store.isThisMac)

        await api.setPlayer(.success(snapshot(playing: true, kind: .speaker, at: clock.now, trackID: "t1")))
        store = makeStore()
        try await store.refresh()
        store.localHint = LocalHint(trackID: "t1", isPlaying: true, at: clock.now)
        #expect(!store.isThisMac)
    }

    @Test func staleAfter60s() async throws {
        await api.setPlayer(.success(snapshot(at: clock.now)))
        let store = makeStore()
        try await store.refresh()
        await api.setPlayer(.failure(.server(500)))
        clock.now = clock.now.addingTimeInterval(30)
        await #expect(throws: SpotifyAPIError.server(500)) { try await store.refresh() }
        #expect(!store.isStale)
        clock.now = clock.now.addingTimeInterval(31)
        await #expect(throws: SpotifyAPIError.server(500)) { try await store.refresh() }
        #expect(store.isStale)
        guard case .active = store.phase else { Issue.record("should keep last state"); return }
    }

    @Test func controlsNotifyOnAction() async throws {
        await api.setPlayer(.success(snapshot(at: clock.now)))
        let store = makeStore()
        try await store.refresh()
        var count = 0
        store.onAction = { count += 1 }
        await store.next()
        await store.transfer(to: Device(id: "d2", name: "TV", kind: .tv, isActive: false, volumePercent: nil, supportsVolume: false))
        #expect(count == 2)
        #expect(await api.calls.contains("transfer:d2"))
    }
}
