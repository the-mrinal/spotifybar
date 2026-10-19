import Foundation
import Testing
@testable import SpotifyBarCore

private let now = Date(timeIntervalSince1970: 4_000_000)

private func ctx(ui: Bool = false, playing: Bool? = true, suspended: Bool = false, errors: Int = 0, retryAfter: TimeInterval? = nil, remaining: Int? = nil) -> PollContext {
    let phase: PlaybackPhase = playing.map { .active(snapshot(playing: $0, at: now)) } ?? .idle
    return PollContext(uiVisible: ui, phase: phase, suspended: suspended, consecutiveErrors: errors, retryAfter: retryAfter, trackRemainingMs: remaining)
}

@Suite struct PollPolicyTests {
    @Test func uiVisibleIs2s() { #expect(PollPolicy.nextDelay(ctx(ui: true)) == 2) }
    @Test func playingIs5s() { #expect(PollPolicy.nextDelay(ctx()) == 5) }
    @Test func pausedIs15s() { #expect(PollPolicy.nextDelay(ctx(playing: false)) == 15) }
    @Test func idleIs30s() { #expect(PollPolicy.nextDelay(ctx(playing: nil)) == 30) }
    @Test func suspendedIsNil() { #expect(PollPolicy.nextDelay(ctx(suspended: true)) == nil) }
    @Test func signedOutIsNil() {
        var c = ctx(); c.phase = .signedOut
        #expect(PollPolicy.nextDelay(c) == nil)
    }
    @Test func schedulesTrackEndFetch() {
        #expect(PollPolicy.nextDelay(ctx(remaining: 1_200)) == 1.5)
        #expect(PollPolicy.nextDelay(ctx(remaining: 60_000)) == 5)
        #expect(PollPolicy.nextDelay(ctx(playing: false, remaining: 1_200)) == 15)
    }
    @Test func honoursRetryAfter() { #expect(PollPolicy.nextDelay(ctx(errors: 1, retryAfter: 20)) == 20) }
    @Test func backsOffExponentially() {
        #expect(PollPolicy.nextDelay(ctx(errors: 1)) == 10)
        #expect(PollPolicy.nextDelay(ctx(errors: 2)) == 20)
        #expect(PollPolicy.nextDelay(ctx(errors: 3)) == 40)
        #expect(PollPolicy.nextDelay(ctx(errors: 4)) == 60)
        #expect(PollPolicy.nextDelay(ctx(errors: 9)) == 60)
    }
}

@MainActor @Suite struct PollSchedulerTests {
    final class Counter { var n = 0 }

    @Test func startFetchesImmediately() async throws {
        let c = Counter()
        let s = PollScheduler(policy: { _ in nil }, context: { ctx() }, fetch: { c.n += 1 }, coalesce: .milliseconds(300))
        s.start()
        try await Task.sleep(for: .milliseconds(100))
        #expect(c.n == 1)
        s.stop()
    }

    @Test func triggerCoalescesWithin1s() async throws {
        let c = Counter()
        let s = PollScheduler(policy: { _ in nil }, context: { ctx() }, fetch: { c.n += 1 }, coalesce: .milliseconds(300))
        s.start()
        try await Task.sleep(for: .milliseconds(50))
        s.trigger(); s.trigger(); s.trigger()
        try await Task.sleep(for: .milliseconds(100))
        #expect(c.n == 1)
        try await Task.sleep(for: .milliseconds(400))
        #expect(c.n == 2)
        s.stop()
    }

    @Test func pollsOnPolicyInterval() async throws {
        let c = Counter()
        let s = PollScheduler(policy: { _ in 0.1 }, context: { ctx() }, fetch: { c.n += 1 }, coalesce: .milliseconds(10))
        s.start()
        try await Task.sleep(for: .milliseconds(350))
        s.stop()
        #expect((3...5).contains(c.n))
        let after = c.n
        try await Task.sleep(for: .milliseconds(250))
        #expect(c.n == after)
    }
}
