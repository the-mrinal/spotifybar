import Foundation

/// What the homelab's speaker service (`speaker.py`, `GET /api/status`) reports about the Bluetooth speaker it feeds.
public struct SpeakerStatus: Sendable, Equatable {
    public struct AirPlay: Sendable, Equatable {
        public var session: Bool
        public var playing: Bool
        public var title: String?
        public var artist: String?
        public var album: String?
        public var clientName: String?
        public var coverStamp: Int?

        public init(session: Bool, playing: Bool, title: String?, artist: String?, album: String?, clientName: String?, coverStamp: Int?) {
            self.session = session
            self.playing = playing
            self.title = title
            self.artist = artist
            self.album = album
            self.clientName = clientName
            self.coverStamp = coverStamp
        }
    }

    public var name: String
    public var connected: Bool
    public var battery: Int?
    public var charging: Bool
    public var volume: Int?
    /// The homelab's Spotify Connect device name.
    public var spotifyDeviceName: String?
    public var airplay: AirPlay
    public var eqPreset: String?
    public var eqPresets: [String]
    public var sleepEndsAt: Date?
    public var sleepChoices: [Int]

    public init(name: String, connected: Bool, battery: Int?, charging: Bool, volume: Int?, spotifyDeviceName: String?,
                airplay: AirPlay, eqPreset: String?, eqPresets: [String], sleepEndsAt: Date?, sleepChoices: [Int]) {
        self.name = name
        self.connected = connected
        self.battery = battery
        self.charging = charging
        self.volume = volume
        self.spotifyDeviceName = spotifyDeviceName
        self.airplay = airplay
        self.eqPreset = eqPreset
        self.eqPresets = eqPresets
        self.sleepEndsAt = sleepEndsAt
        self.sleepChoices = sleepChoices
    }

    public var isBatteryLow: Bool {
        guard connected, let battery, !charging else { return false }
        return battery < 20
    }
}

// MARK: - DTOs

struct SpeakerStatusDTO: Decodable {
    struct Speaker: Decodable {
        let name: String?
        let connected: Bool
        let battery: Int?
        let charging: Bool?
        let volume: Int?
    }
    struct Spotify: Decodable { let device_name: String? }
    struct AirPlay: Decodable {
        let session: Bool?
        let playing: Bool?
        let title: String?
        let artist: String?
        let album: String?
        let client_name: String?
        let cover_ts: Int?
    }
    struct EQ: Decodable {
        let preset: String?
        let presets: [String]?
        let available: Bool?
    }
    struct Sleep: Decodable {
        let ends_at: Double?
        let choices: [Int]?
    }

    let speaker: Speaker
    let spotify: Spotify?
    let airplay: AirPlay?
    let eq: EQ?
    let sleep: Sleep?
}

public enum SpeakerDecoder {
    public static func decode(_ data: Data) throws -> SpeakerStatus {
        let dto = try JSONDecoder().decode(SpeakerStatusDTO.self, from: data)
        let a = dto.airplay
        let eqOn = dto.eq?.available ?? false
        return SpeakerStatus(
            name: dto.speaker.name ?? "Speaker",
            connected: dto.speaker.connected,
            battery: dto.speaker.battery,
            charging: dto.speaker.charging ?? false,
            volume: dto.speaker.volume,
            spotifyDeviceName: dto.spotify?.device_name,
            airplay: .init(session: a?.session ?? false, playing: a?.playing ?? false, title: nonEmpty(a?.title),
                           artist: nonEmpty(a?.artist), album: nonEmpty(a?.album), clientName: nonEmpty(a?.client_name),
                           coverStamp: a?.cover_ts),
            eqPreset: eqOn ? dto.eq?.preset : nil,
            eqPresets: eqOn ? dto.eq?.presets ?? [] : [],
            sleepEndsAt: dto.sleep?.ends_at.map(Date.init(timeIntervalSince1970:)),
            sleepChoices: dto.sleep?.choices ?? [])
    }

    /// shairport-sync reports missing fields as "--".
    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty, s != "--" else { return nil }
        return s
    }
}

// MARK: - Client

public protocol SpeakerAPIClient: Sendable {
    func status() async throws -> SpeakerStatus
    func setVolume(_ percent: Int) async throws -> SpeakerStatus
    func setEQ(_ preset: String) async throws -> SpeakerStatus
    func setSleep(minutes: Int) async throws -> SpeakerStatus
    func connect() async throws -> SpeakerStatus
    func coverURL(stamp: Int?) -> URL
}

public struct SpeakerAPIError: Error, Equatable, Sendable {
    public var message: String
}

public final class URLSessionSpeakerAPI: SpeakerAPIClient {
    private let base: URL
    private let session: URLSession

    public init(base: URL, session: URLSession? = nil) {
        self.base = base
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 4
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    public func status() async throws -> SpeakerStatus { try await send("GET", "api/status") }
    public func setVolume(_ percent: Int) async throws -> SpeakerStatus {
        try await send("POST", "api/speaker/volume", ["value": min(100, max(0, percent))])
    }
    public func setEQ(_ preset: String) async throws -> SpeakerStatus { try await send("POST", "api/eq", ["preset": preset]) }
    public func setSleep(minutes: Int) async throws -> SpeakerStatus { try await send("POST", "api/sleep", ["minutes": minutes]) }
    public func connect() async throws -> SpeakerStatus { try await send("POST", "api/speaker/connect", [:]) }

    public func coverURL(stamp: Int?) -> URL {
        var c = URLComponents(url: base.appending(path: "api/airplay/cover"), resolvingAgainstBaseURL: false)!
        // The stamp only makes the URL unique per cover so the art cache doesn't serve a stale image.
        c.queryItems = [URLQueryItem(name: "ts", value: String(stamp ?? 0))]
        return c.url!
    }

    private func send(_ method: String, _ path: String, _ body: [String: Any]? = nil) async throws -> SpeakerStatus {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch { throw SpeakerAPIError(message: "Homelab not reachable") }
        guard let http = response as? HTTPURLResponse else { throw SpeakerAPIError(message: "Homelab not reachable") }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw SpeakerAPIError(message: message ?? "Homelab error \(http.statusCode)")
        }
        return try SpeakerDecoder.decode(data)
    }
}

// MARK: - Route

/// Where the sound actually comes out, and therefore what the volume slider controls.
public enum AudioRoute: Equatable, Sendable {
    /// Spotify plays on its own device; the slider is Spotify's device volume.
    case spotify
    /// The homelab's own Spotify Connect device feeds the speaker.
    case speakerDirect
    /// An AirPlay sender feeds the speaker. `fromThisMac` means the Mac's output volume drives the speaker.
    case speakerAirPlay(sender: String, fromThisMac: Bool)

    public var reachesSpeaker: Bool { self != .spotify }

    /// - Parameters:
    ///   - spotifyDeviceName: the active Spotify device, if any.
    ///   - macOutputIsAirPlay: the Mac's default output device is an AirPlay device.
    ///   - macName: the Mac's computer name, compared with the AirPlay sender's name.
    public static func resolve(speaker: SpeakerStatus?, spotifyDeviceName: String?, macOutputIsAirPlay: Bool, macName: String?) -> AudioRoute {
        guard let speaker, speaker.connected else { return .spotify }
        if let name = spotifyDeviceName, let own = speaker.spotifyDeviceName, name == own { return .speakerDirect }
        guard speaker.airplay.session else { return .spotify }
        let client = speaker.airplay.clientName
        // The receiver takes one session at a time. If the Mac outputs to AirPlay and the sender looks like a Mac
        // (or is unnamed), the Mac is the sender; a phone sender means the Mac is AirPlaying somewhere else.
        let looksLikeMac = client.map { $0.localizedCaseInsensitiveContains("mac") } ?? true
        let fromMac = (client != nil && client == macName) || (macOutputIsAirPlay && looksLikeMac)
        return .speakerAirPlay(sender: fromMac ? "This Mac" : shortName(client ?? "AirPlay"), fromThisMac: fromMac)
    }

    /// "Mrinal’s iPhone" → "iPhone".
    public static func shortName(_ name: String) -> String {
        for mark in ["’s ", "'s "] {
            if let range = name.range(of: mark), range.upperBound < name.endIndex {
                return String(name[range.upperBound...])
            }
        }
        return name
    }
}

/// What the volume slider moves, given the route.
public enum VolumeTarget: Equatable, Sendable {
    case spotify
    case speaker
    case macOutput

    public init(route: AudioRoute) {
        switch route {
        case .spotify: self = .spotify
        case .speakerDirect: self = .speaker
        case .speakerAirPlay(_, let fromThisMac): self = fromThisMac ? .macOutput : .speaker
        }
    }
}
