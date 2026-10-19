import Foundation
import Testing
@testable import SpotifyBarCore

private func status(connected: Bool = true, session: Bool = false, client: String? = nil, battery: Int? = 60, charging: Bool = false) -> SpeakerStatus {
    SpeakerStatus(name: "Xiaomi Sound Outdoor", connected: connected, battery: battery, charging: charging, volume: 44,
                  spotifyDeviceName: "Xiaomi Soundbar",
                  airplay: .init(session: session, playing: session, title: session ? "Song" : nil, artist: nil, album: nil,
                                 clientName: client, coverStamp: 7),
                  eqPreset: "bass", eqPresets: ["flat", "bass"], sleepEndsAt: nil, sleepChoices: [0, 15])
}

@Suite struct SpeakerDecodingTests {
    @Test func decodesHomelabStatus() throws {
        let url = try #require(Bundle(for: FixtureAnchor.self).url(forResource: "speaker_status", withExtension: "json"))
        let s = try SpeakerDecoder.decode(Data(contentsOf: url))
        #expect(s.name == "Xiaomi Sound Outdoor")
        #expect(s.connected && s.battery == 60 && !s.charging && s.volume == 44)
        #expect(s.spotifyDeviceName == "Xiaomi Soundbar")
        #expect(s.airplay.session && s.airplay.playing)
        #expect(s.airplay.title == "Ishq Hai")
        #expect(s.airplay.clientName == "Mrinal’s iPhone")
        #expect(s.airplay.coverStamp == 1792418496)
        #expect(s.eqPreset == "bass")
        #expect(s.eqPresets.count == 6)
        #expect(s.sleepEndsAt == nil)
        #expect(s.sleepChoices == [0, 15, 30, 45, 60, 90, 120])
    }

    @Test func dashesAreMissing() throws {
        let json = #"{"speaker":{"connected":false},"airplay":{"session":true,"title":"--","artist":""},"eq":{"available":false,"preset":"flat","presets":["flat"]}}"#
        let s = try SpeakerDecoder.decode(Data(json.utf8))
        #expect(s.airplay.title == nil && s.airplay.artist == nil)
        #expect(s.eqPreset == nil && s.eqPresets.isEmpty)
        #expect(!s.connected)
    }

    @Test func lowBatteryNeedsConnectedAndNotCharging() {
        #expect(status(battery: 15).isBatteryLow)
        #expect(!status(battery: 15, charging: true).isBatteryLow)
        #expect(!status(connected: false, battery: 15).isBatteryLow)
        #expect(!status(battery: 20).isBatteryLow)
    }
}

@Suite struct AudioRouteTests {
    let mac = "Mrinal’s MacBook Pro (2)"

    @Test func noSpeakerMeansSpotify() {
        #expect(AudioRoute.resolve(speaker: nil, spotifyDeviceName: "iPhone", macOutputIsAirPlay: true, macName: mac) == .spotify)
        #expect(AudioRoute.resolve(speaker: status(connected: false, session: true), spotifyDeviceName: nil, macOutputIsAirPlay: false, macName: mac) == .spotify)
    }

    @Test func homelabSpotifyDeviceIsDirect() {
        let r = AudioRoute.resolve(speaker: status(), spotifyDeviceName: "Xiaomi Soundbar", macOutputIsAirPlay: false, macName: mac)
        #expect(r == .speakerDirect)
        #expect(VolumeTarget(route: r) == .speaker)
    }

    @Test func phoneAirPlayDrivesSpeakerVolume() {
        let r = AudioRoute.resolve(speaker: status(session: true, client: "Mrinal’s iPhone"), spotifyDeviceName: "Mrinal’s iPhone",
                                   macOutputIsAirPlay: false, macName: mac)
        #expect(r == .speakerAirPlay(sender: "iPhone", fromThisMac: false))
        #expect(VolumeTarget(route: r) == .speaker)
    }

    @Test func macAirPlayDrivesMacOutput() {
        let byName = AudioRoute.resolve(speaker: status(session: true, client: mac), spotifyDeviceName: "MacBook", macOutputIsAirPlay: false, macName: mac)
        #expect(byName == .speakerAirPlay(sender: "This Mac", fromThisMac: true))
        let byOutput = AudioRoute.resolve(speaker: status(session: true, client: "MacBook Pro"), spotifyDeviceName: nil, macOutputIsAirPlay: true, macName: "Other")
        #expect(VolumeTarget(route: byOutput) == .macOutput)
    }

    @Test func macAirPlayingElsewhereWhilePhoneFeedsSpeaker() {
        let r = AudioRoute.resolve(speaker: status(session: true, client: "Mrinal’s iPhone"), spotifyDeviceName: nil, macOutputIsAirPlay: true, macName: mac)
        #expect(r == .speakerAirPlay(sender: "iPhone", fromThisMac: false))
    }

    @Test func noSessionAndOtherDeviceIsSpotify() {
        #expect(AudioRoute.resolve(speaker: status(), spotifyDeviceName: "Kitchen", macOutputIsAirPlay: false, macName: mac) == .spotify)
    }

    @Test func shortNames() {
        #expect(AudioRoute.shortName("Mrinal’s iPhone") == "iPhone")
        #expect(AudioRoute.shortName("Anna's iPad") == "iPad")
        #expect(AudioRoute.shortName("Living Room") == "Living Room")
    }
}

actor MockSpeakerAPI: SpeakerAPIClient {
    var current: SpeakerStatus
    var fail = false
    var calls: [String] = []

    init(_ s: SpeakerStatus) { current = s }
    func setFail(_ f: Bool) { fail = f }

    private func reply(_ call: String, _ change: (inout SpeakerStatus) -> Void = { _ in }) throws -> SpeakerStatus {
        calls.append(call)
        if fail { throw SpeakerAPIError(message: "nope") }
        change(&current)
        return current
    }

    func status() async throws -> SpeakerStatus { try reply("status") }
    func setVolume(_ p: Int) async throws -> SpeakerStatus { try reply("volume:\(p)") { $0.volume = p } }
    func setEQ(_ preset: String) async throws -> SpeakerStatus { try reply("eq:\(preset)") { $0.eqPreset = preset } }
    func setSleep(minutes: Int) async throws -> SpeakerStatus { try reply("sleep:\(minutes)") }
    func connect() async throws -> SpeakerStatus { try reply("connect") }
    nonisolated func coverURL(stamp: Int?) -> URL { URL(string: "http://x/cover?ts=\(stamp ?? 0)")! }
}

@MainActor @Suite struct SpeakerStoreTests {
    @Test func refreshAndControls() async {
        let api = MockSpeakerAPI(status())
        let store = SpeakerStore(api: api)
        await store.refresh()
        #expect(store.status?.volume == 44)
        await store.setVolume(130)
        #expect(store.status?.volume == 100)
        #expect(await api.calls.last == "volume:100")
        await store.setEQ("flat")
        #expect(store.status?.eqPreset == "flat")
    }

    @Test func failedControlReverts() async {
        let api = MockSpeakerAPI(status())
        let store = SpeakerStore(api: api)
        await store.refresh()
        await api.setFail(true)
        await store.setVolume(10)
        #expect(store.status?.volume == 44)
        #expect(store.lastError == "nope")
    }

    @Test func hidesAfterTwoMissedPolls() async {
        let api = MockSpeakerAPI(status())
        let store = SpeakerStore(api: api)
        await store.refresh()
        await api.setFail(true)
        await store.refresh()
        #expect(store.status != nil)
        await store.refresh()
        #expect(store.status == nil)
    }

    @Test func coverOnlyDuringSession() async {
        let store = SpeakerStore(api: MockSpeakerAPI(status(session: true)))
        await store.refresh()
        #expect(store.coverURL() == URL(string: "http://x/cover?ts=7"))
    }
}
