import Foundation
import Testing
@testable import SpotifyBarCore

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle(for: FixtureAnchor.self).url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}
final class FixtureAnchor {}

private let now = Date(timeIntervalSince1970: 1_000_000)

@Suite struct APIDecodingTests {
    @Test func decodesTrack() throws {
        let s = try #require(try PlayerDecoder.decode(fixture("track"), status: 200, now: now))
        #expect(s.track.id == "trk1")
        #expect(s.track.title == "Glasshouse Weather")
        #expect(s.track.artist == "Mara Lindqvist, Ola Berg")
        #expect(s.track.album == "Low Light")
        #expect(s.track.durationMs == 214_000)
        #expect(s.track.artSmall == URL(string: "https://i.scdn.co/image/64"))
        #expect(s.track.artMedium == URL(string: "https://i.scdn.co/image/300"))
        #expect(s.track.isAd == false)
        #expect(s.device.kind == .speaker)
        #expect(s.device.name == "Kitchen")
        #expect(s.device.volumePercent == 42)
        #expect(s.device.supportsVolume)
        #expect(s.isPlaying)
        #expect(s.progressMs == 61_000)
        #expect(s.fetchedAt == now)
    }

    @Test func decodesEpisode() throws {
        let s = try #require(try PlayerDecoder.decode(fixture("episode"), status: 200, now: now))
        #expect(s.track.title == "Episode 12")
        #expect(s.track.artist == "The Show")
        #expect(s.track.artSmall == URL(string: "https://i.scdn.co/image/ep64"))
        #expect(s.track.artMedium == URL(string: "https://i.scdn.co/image/ep300"))
        #expect(s.device.kind == .smartphone)
        #expect(!s.isPlaying)
    }

    @Test func decodesAd() throws {
        let s = try #require(try PlayerDecoder.decode(fixture("ad"), status: 200, now: now))
        #expect(s.track.isAd)
        #expect(s.track.title == "Advertisement")
        #expect(s.device.kind == .tv)
    }

    @Test func decodesNoVolume() throws {
        let s = try #require(try PlayerDecoder.decode(fixture("no_volume"), status: 200, now: now))
        #expect(s.device.supportsVolume == false)
        #expect(s.device.volumePercent == nil)
        #expect(s.device.kind == .automobile)
        #expect(s.track.artSmall == nil)
    }

    @Test func decodes204AsNil() throws {
        #expect(try PlayerDecoder.decode(Data(), status: 204, now: now) == nil)
    }

    @Test func mapsStatusErrors() {
        #expect(SpotifyAPIError.map(status: 401, headers: [:]) == .unauthorized)
        #expect(SpotifyAPIError.map(status: 429, headers: ["Retry-After": "7"]) == .rateLimited(retryAfter: 7))
        #expect(SpotifyAPIError.map(status: 404, headers: [:]) == .notFound)
        #expect(SpotifyAPIError.map(status: 403, headers: [:]) == .forbidden)
        #expect(SpotifyAPIError.map(status: 502, headers: [:]) == .server(502))
    }

    @Test func decodesDevices() throws {
        let json = #"{"devices":[{"id":"a","is_active":false,"name":"MacBook","type":"Computer","volume_percent":50,"supports_volume":true},{"id":null,"is_active":false,"name":"Restricted","type":"Speaker","volume_percent":null,"supports_volume":false}]}"#
        let devices = try PlayerDecoder.decodeDevices(Data(json.utf8))
        #expect(devices.map(\.id) == ["a"])
        #expect(devices.first?.kind == .computer)
    }
}
