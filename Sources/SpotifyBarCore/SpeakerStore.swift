import Foundation
import Observation

/// The homelab speaker's last known state. `status` is nil while it's off, unconfigured or unreachable,
/// so every speaker feature hides and the app behaves as if it didn't exist.
@MainActor @Observable
public final class SpeakerStore {
    public private(set) var status: SpeakerStatus?
    public private(set) var lastError: String?
    @ObservationIgnored public private(set) var consecutiveFailures = 0

    @ObservationIgnored public var api: SpeakerAPIClient? {
        didSet { if api == nil { status = nil; consecutiveFailures = 0 } }
    }
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var lastErrorAt: Date?

    public init(api: SpeakerAPIClient?, now: @escaping () -> Date = Date.init) {
        self.api = api
        self.now = now
    }

    public func refresh() async {
        guard let api else { return }
        do {
            apply(try await api.status())
        } catch {
            consecutiveFailures += 1
            // One missed poll (Wi-Fi blip) keeps the last state; two in a row hides the speaker.
            if consecutiveFailures >= 2 { status = nil }
        }
    }

    public func setVolume(_ percent: Int) async {
        let clamped = min(100, max(0, percent))
        await perform({ $0.volume = clamped }) { try await $0.setVolume(clamped) }
    }

    public func setEQ(_ preset: String) async {
        await perform({ $0.eqPreset = preset }) { try await $0.setEQ(preset) }
    }

    public func setSleep(minutes: Int) async {
        let ends = minutes > 0 ? now().addingTimeInterval(TimeInterval(minutes * 60)) : nil
        await perform({ $0.sleepEndsAt = ends }) { try await $0.setSleep(minutes: minutes) }
    }

    public func connect() async {
        await perform({ _ in }) { try await $0.connect() }
    }

    public func coverURL() -> URL? {
        guard let status, status.airplay.session else { return nil }
        return api?.coverURL(stamp: status.airplay.coverStamp)
    }

    /// Applies `optimistic` right away, then the service's fresh status; reverts if the request fails.
    private func perform(_ optimistic: (inout SpeakerStatus) -> Void, _ action: (SpeakerAPIClient) async throws -> SpeakerStatus) async {
        guard let api else { return }
        let previous = status
        if var s = status { optimistic(&s); status = s }
        do {
            apply(try await action(api))
            lastError = nil
        } catch {
            status = previous
            lastError = (error as? SpeakerAPIError)?.message ?? "Homelab not reachable"
            lastErrorAt = now()
        }
    }

    private func apply(_ fresh: SpeakerStatus) {
        // Assigning an equal value still notifies observers, and the menu bar shouldn't redraw on every poll.
        if status != fresh { status = fresh }
        consecutiveFailures = 0
        if let at = lastErrorAt, now().timeIntervalSince(at) > 4 { lastError = nil; lastErrorAt = nil }
    }
}
