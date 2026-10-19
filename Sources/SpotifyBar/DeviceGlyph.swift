import SpotifyBarCore

func deviceSymbol(_ kind: DeviceKind) -> String {
    switch kind {
    case .computer: "laptopcomputer"
    case .smartphone: "iphone"
    case .speaker: "hifispeaker"
    case .tv, .castVideo, .stb: "tv"
    case .automobile: "car"
    case .avr, .castAudio, .audioDongle: "hifispeaker.2"
    case .gameConsole: "gamecontroller"
    case .unknown: "speaker.wave.2"
    }
}

extension PlaybackStore {
    /// "This Mac" when the local client is playing, otherwise the Spotify device name.
    var deviceDisplayName: String {
        guard let s = snapshot else { return "" }
        return isThisMac ? "This Mac" : s.device.name
    }
}

func batterySymbol(_ percent: Int, charging: Bool) -> String {
    if charging { return "battery.100percent.bolt" }
    switch percent {
    case ..<13: return "battery.0percent"
    case ..<38: return "battery.25percent"
    case ..<63: return "battery.50percent"
    case ..<88: return "battery.75percent"
    default: return "battery.100percent"
    }
}

extension AppModel {
    /// The glyph for where the sound comes out: the speaker when it reaches the homelab speaker.
    var routeSymbol: String {
        if route.reachesSpeaker || airPlayOnly != nil { return "hifispeaker" }
        return store.snapshot.map { deviceSymbol($0.device.kind) } ?? "hifispeaker"
    }

    /// "iPhone → Xiaomi Sound Outdoor" when a sender feeds the speaker, otherwise the Spotify device.
    var routeDisplayName: String {
        guard let speakerName = speaker.status?.name else { return store.deviceDisplayName }
        switch route {
        case .spotify: return store.deviceDisplayName
        case .speakerDirect: return speakerName
        case .speakerAirPlay(let sender, _): return "\(sender) → \(speakerName)"
        }
    }
}
