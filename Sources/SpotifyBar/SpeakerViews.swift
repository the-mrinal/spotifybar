import SpotifyBarCore
import SwiftUI

/// Small battery glyph and percentage; tinted only when low.
struct BatteryBadge: View {
    let speaker: SpeakerStore

    var body: some View {
        if let s = speaker.status, s.connected, let battery = s.battery {
            HStack(spacing: 3) {
                Image(systemName: batterySymbol(battery, charging: s.charging)).font(.system(size: 11))
                Text("\(battery)%").font(.system(size: 10.5, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(s.isBatteryLow ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
            .help(s.charging ? "\(s.name): \(battery)%, charging" : "\(s.name): \(battery)%")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Speaker battery \(battery) percent\(s.charging ? ", charging" : "")")
        }
    }
}

/// Speaker extras for the remote: Spotify volume nudge, direct play, EQ, sleep timer and link health.
struct SpeakerControls: View {
    let model: AppModel

    private var speaker: SpeakerStore { model.speaker }

    var body: some View {
        if let s = speaker.status {
            VStack(alignment: .leading, spacing: 9) {
                if !s.connected {
                    HStack(spacing: 6) {
                        Image(systemName: "hifispeaker.fill").font(.system(size: 11))
                        Text("\(s.name) disconnected").font(.system(size: 11.5))
                        Spacer()
                        Button("Reconnect") { Task { await speaker.connect() } }
                            .buttonStyle(.link).font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                } else if model.route.reachesSpeaker || model.airPlayOnly != nil {
                    if let capped = model.spotifyVolumeCapping {
                        HStack(spacing: 6) {
                            Text("Spotify is at \(capped)%").font(.system(size: 11)).foregroundStyle(.tertiary)
                            Button("Set to 100%") { Task { await model.store.setVolume(100) } }
                                .buttonStyle(.link).font(.system(size: 11, weight: .medium))
                        }
                    }
                    if let direct = model.directSpeakerDevice {
                        Button { Task { await model.store.transfer(to: direct) } } label: {
                            Label("Play on \(s.name) directly", systemImage: "arrow.triangle.branch")
                                .font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .frame(height: 26)
                                .background(Capsule().fill(.primary.opacity(0.08)))
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .help("Hand Spotify to the homelab so the phone stops streaming")
                    }
                    HStack(spacing: 8) {
                        if !s.eqPresets.isEmpty { EQRow(speaker: speaker, status: s) }
                        Spacer(minLength: 0)
                        SleepMenu(speaker: speaker, status: s)
                    }
                }
                if let error = speaker.lastError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                }
            }
        }
    }
}

private struct EQRow: View {
    let speaker: SpeakerStore
    let status: SpeakerStatus

    var body: some View {
        HStack(spacing: 2) {
            // "custom" is set from the homelab dashboard's sliders; offering it here would just reapply them.
            ForEach(status.eqPresets.filter { $0 != "custom" || status.eqPreset == "custom" }, id: \.self) { preset in
                let selected = preset == status.eqPreset
                Button { Task { await speaker.setEQ(preset) } } label: {
                    Text(preset.capitalized)
                        .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? .primary : .secondary)
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                        .background(Capsule().fill(.primary.opacity(selected ? 0.14 : 0)))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("EQ \(preset)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

private struct SleepMenu: View {
    let speaker: SpeakerStore
    let status: SpeakerStatus

    var body: some View {
        Menu {
            ForEach(status.sleepChoices.filter { $0 > 0 }, id: \.self) { minutes in
                Button(minutes < 60 || minutes % 60 != 0 ? "\(minutes) min" : "\(minutes / 60) h") {
                    Task { await speaker.setSleep(minutes: minutes) }
                }
            }
            if status.sleepEndsAt != nil {
                Divider()
                Button("Turn Off") { Task { await speaker.setSleep(minutes: 0) } }
            }
        } label: {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(spacing: 3) {
                    Image(systemName: "moon.zzz").font(.system(size: 11))
                    if let ends = status.sleepEndsAt {
                        let left = max(1, Int(ends.timeIntervalSince(context.date) / 60 + 0.5))
                        Text("\(left) min").font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    }
                }
                .foregroundStyle(status.sleepEndsAt == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(status.sleepEndsAt == nil ? "Sleep timer" : "Sleep timer is on")
        .accessibilityLabel("Sleep timer")
    }
}

/// Now playing for AirPlay from a non-Spotify app; there's no way to control the sender, so no transport.
struct AirPlayNowPlaying: View {
    let model: AppModel
    let airplay: SpeakerStatus.AirPlay
    var artSize: CGFloat

    var body: some View {
        HStack(alignment: artSize > 60 ? .top : .center, spacing: artSize > 60 ? 13 : 10) {
            ArtView(url: model.speaker.coverURL(), art: model.art, size: artSize, radius: artSize > 60 ? 10 : 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(airplay.title ?? "AirPlay").font(.system(size: artSize > 60 ? 15 : 13, weight: .semibold)).lineLimit(2)
                if let artist = airplay.artist {
                    Text(artist).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                if artSize > 60, let album = airplay.album {
                    Text(album).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.top, artSize > 60 ? 4 : 0)
        }
    }
}
