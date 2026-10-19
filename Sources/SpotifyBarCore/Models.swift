import Foundation

public enum DeviceKind: String, Sendable, Equatable {
    case computer, smartphone, speaker, tv, avr, stb, audioDongle, gameConsole, castVideo, castAudio, automobile, unknown

    init(apiType: String) {
        switch apiType.lowercased() {
        case "computer": self = .computer
        case "smartphone", "tablet": self = .smartphone
        case "speaker": self = .speaker
        case "tv": self = .tv
        case "avr": self = .avr
        case "stb": self = .stb
        case "audiodongle": self = .audioDongle
        case "gameconsole": self = .gameConsole
        case "castvideo": self = .castVideo
        case "castaudio": self = .castAudio
        case "automobile": self = .automobile
        default: self = .unknown
        }
    }
}

public struct Device: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var kind: DeviceKind
    public var isActive: Bool
    public var volumePercent: Int?
    public var supportsVolume: Bool

    public init(id: String, name: String, kind: DeviceKind, isActive: Bool, volumePercent: Int?, supportsVolume: Bool) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isActive = isActive
        self.volumePercent = volumePercent
        self.supportsVolume = supportsVolume
    }
}

public struct Track: Sendable, Equatable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var durationMs: Int
    public var artSmall: URL?
    public var artMedium: URL?
    public var isAd: Bool

    public init(id: String, title: String, artist: String, album: String, durationMs: Int, artSmall: URL?, artMedium: URL?, isAd: Bool) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationMs = durationMs
        self.artSmall = artSmall
        self.artMedium = artMedium
        self.isAd = isAd
    }
}

public struct PlayerSnapshot: Sendable, Equatable {
    public var track: Track
    public var device: Device
    public var isPlaying: Bool
    public var progressMs: Int
    public var fetchedAt: Date

    public init(track: Track, device: Device, isPlaying: Bool, progressMs: Int, fetchedAt: Date) {
        self.track = track
        self.device = device
        self.isPlaying = isPlaying
        self.progressMs = progressMs
        self.fetchedAt = fetchedAt
    }
}

// MARK: - Web API DTOs

struct ImageDTO: Decodable { let url: URL; let width: Int?; let height: Int? }
struct ArtistDTO: Decodable { let name: String }
struct AlbumDTO: Decodable { let name: String; let images: [ImageDTO] }
struct ShowDTO: Decodable { let name: String; let images: [ImageDTO] }

struct ItemDTO: Decodable {
    let id: String?
    let name: String
    let duration_ms: Int
    let artists: [ArtistDTO]?
    let album: AlbumDTO?
    let images: [ImageDTO]?
    let show: ShowDTO?
}

struct DeviceDTO: Decodable {
    let id: String?
    let is_active: Bool
    let name: String
    let type: String
    let volume_percent: Int?
    let supports_volume: Bool?

    var model: Device? {
        guard let id else { return nil }
        return Device(id: id, name: name, kind: DeviceKind(apiType: type), isActive: is_active,
                      volumePercent: volume_percent, supportsVolume: supports_volume ?? (volume_percent != nil))
    }
}

struct PlayerDTO: Decodable {
    let device: DeviceDTO?
    let progress_ms: Int?
    let is_playing: Bool
    let currently_playing_type: String?
    let item: ItemDTO?
}

struct DevicesDTO: Decodable { let devices: [DeviceDTO] }

/// Picks the smallest image at least `minSide` px wide, falling back to the largest available.
func pickImage(_ images: [ImageDTO], minSide: Int) -> URL? {
    let sorted = images.sorted { ($0.width ?? 0) < ($1.width ?? 0) }
    return (sorted.first { ($0.width ?? 0) >= minSide } ?? sorted.last)?.url
}

public enum PlayerDecoder {
    public static func decode(_ data: Data, status: Int, now: Date) throws -> PlayerSnapshot? {
        if status == 204 || data.isEmpty { return nil }
        let dto = try JSONDecoder().decode(PlayerDTO.self, from: data)
        guard let device = dto.device?.model else { return nil }

        let track: Track
        if dto.currently_playing_type == "ad" {
            track = Track(id: "ad", title: "Advertisement", artist: "Spotify", album: "",
                          durationMs: dto.item?.duration_ms ?? 30_000, artSmall: nil, artMedium: nil, isAd: true)
        } else if let item = dto.item {
            let images = item.album?.images ?? item.images ?? item.show?.images ?? []
            let artist = item.artists?.map(\.name).joined(separator: ", ") ?? item.show?.name ?? ""
            track = Track(id: item.id ?? item.name, title: item.name, artist: artist, album: item.album?.name ?? item.show?.name ?? "",
                          durationMs: item.duration_ms, artSmall: pickImage(images, minSide: 64),
                          artMedium: pickImage(images, minSide: 300), isAd: false)
        } else {
            return nil
        }
        return PlayerSnapshot(track: track, device: device, isPlaying: dto.is_playing,
                              progressMs: dto.progress_ms ?? 0, fetchedAt: now)
    }

    public static func decodeDevices(_ data: Data) throws -> [Device] {
        try JSONDecoder().decode(DevicesDTO.self, from: data).devices.compactMap(\.model)
    }
}
