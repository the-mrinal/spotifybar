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
