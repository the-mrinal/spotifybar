import Foundation

public struct PollContext: Equatable, Sendable {
    public var uiVisible: Bool
    public var phase: PlaybackPhase
    public var suspended: Bool
    public var consecutiveErrors: Int
    public var retryAfter: TimeInterval?
    public var trackRemainingMs: Int?

    public init(uiVisible: Bool, phase: PlaybackPhase, suspended: Bool, consecutiveErrors: Int, retryAfter: TimeInterval?, trackRemainingMs: Int?) {
        self.uiVisible = uiVisible
        self.phase = phase
        self.suspended = suspended
        self.consecutiveErrors = consecutiveErrors
        self.retryAfter = retryAfter
        self.trackRemainingMs = trackRemainingMs
    }
}

public enum PollPolicy {
    /// Seconds until the next poll, or nil to stop polling until something changes.
    public static func nextDelay(_ c: PollContext) -> TimeInterval? {
        if c.suspended { return nil }
        if let retryAfter = c.retryAfter { return retryAfter }

        let base: TimeInterval
        var isPlaying = false
        switch c.phase {
        case .signedOut: return nil
        case .idle: base = c.uiVisible ? 2 : 30
        case .active(let s):
            isPlaying = s.isPlaying
            base = c.uiVisible ? 2 : (s.isPlaying ? 5 : 15)
        }

        if c.consecutiveErrors > 0 {
            return min(60, max(10, base * pow(2, Double(c.consecutiveErrors))))
        }
        if isPlaying, let remaining = c.trackRemainingMs {
            return min(base, (Double(remaining) + 300) / 1000)
        }
        return base
    }
}

/// Runs one fetch loop. Event triggers replace the next scheduled poll and are coalesced.
@MainActor
public final class PollScheduler {
    private let policy: (PollContext) -> TimeInterval?
    private let context: () -> PollContext
    private let fetch: () async -> Void
    private let coalesce: Duration
    private let clock = ContinuousClock()

    private var loop: Task<Void, Never>?
    private var running = false
    private var fetching = false
    private var pendingTrigger = false
    private var lastFetchStart: ContinuousClock.Instant?

    public init(policy: @escaping (PollContext) -> TimeInterval? = PollPolicy.nextDelay,
                context: @escaping () -> PollContext,
                fetch: @escaping () async -> Void,
                coalesce: Duration = .seconds(1)) {
        self.policy = policy
        self.context = context
        self.fetch = fetch
        self.coalesce = coalesce
    }

    public func start() {
        running = true
        schedule(after: .zero)
    }

    public func stop() {
        running = false
        loop?.cancel()
        loop = nil
    }

    public func trigger() {
        guard running else { return }
        if fetching { pendingTrigger = true; return }
        schedule(after: coalesceWait())
    }

    public func contextChanged() {
        guard running, !fetching else { return }
        schedule(after: policyDelay())
    }

    private func coalesceWait() -> Duration {
        guard let last = lastFetchStart else { return .zero }
        let elapsed = clock.now - last
        return elapsed >= coalesce ? .zero : coalesce - elapsed
    }

    private func policyDelay() -> Duration? {
        policy(context()).map { .milliseconds(Int($0 * 1000)) }
    }

    private func schedule(after initial: Duration?) {
        loop?.cancel()
        guard let initial else { loop = nil; return }
        loop = Task { [weak self] in
            var delay: Duration? = initial
            while let wait = delay {
                do { try await Task.sleep(for: wait) } catch { return }
                guard let self, self.running else { return }
                self.fetching = true
                self.lastFetchStart = self.clock.now
                await self.fetch()
                self.fetching = false
                if Task.isCancelled { return }
                if self.pendingTrigger {
                    self.pendingTrigger = false
                    delay = self.coalesceWait()
                } else {
                    delay = self.policyDelay()
                }
            }
        }
    }
}
