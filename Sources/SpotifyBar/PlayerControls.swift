import SpotifyBarCore
import SwiftUI

/// Shared rows used by the hover card and the remote panel.
struct ProgressRow: View {
    let store: PlaybackStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let s = store.snapshot
            let progress = store.progressMs(at: context.date)
            let duration = max(s?.track.durationMs ?? 1, 1)
            HStack(spacing: 8) {
                Text(Self.format(progress)).frame(minWidth: 27, alignment: .leading)
                GeometryReader { geo in
                    Capsule().fill(.primary.opacity(0.18))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.primary).frame(width: geo.size.width * CGFloat(progress) / CGFloat(duration))
                        }
                }
                .frame(height: 4)
                Text("−" + Self.format(duration - progress)).frame(minWidth: 27, alignment: .trailing)
            }
            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    static func format(_ ms: Int) -> String {
        let total = max(0, ms) / 1000
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct TransportRow: View {
    let store: PlaybackStore

    var body: some View {
        let playing = store.snapshot?.isPlaying ?? false
        HStack(spacing: 18) {
            RoundButton(symbol: "backward.fill", size: 32, label: "Previous track") { Task { await store.previous() } }
            RoundButton(symbol: playing ? "pause.fill" : "play.fill", size: 40, filled: true, label: playing ? "Pause" : "Play") {
                Task { await store.togglePlay() }
            }
            RoundButton(symbol: "forward.fill", size: 32, label: "Next track") { Task { await store.next() } }
        }
        .frame(maxWidth: .infinity)
    }
}

struct RoundButton: View {
    let symbol: String
    let size: CGFloat
    var filled = false
    let label: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size >= 40 ? 18 : 16, weight: .semibold))
                .frame(width: size, height: size)
                .background(Circle().fill(.primary.opacity(filled ? (hover ? 0.18 : 0.11) : (hover ? 0.1 : 0))))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(label)
    }
}

/// Volume slider that sends at most one request per 150 ms while dragging, and the final value on release.
/// It turns whatever the sound is actually coming out of (see `AppModel.volumeTarget`).
struct VolumeRow: View {
    let model: AppModel
    @State private var value: Double = 50
    @State private var editing = false
    @State private var pending: Task<Void, Never>?

    var body: some View {
        let enabled = model.volumeEnabled
        let hasSource = model.store.snapshot != nil || model.airPlayOnly != nil
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                Image(systemName: "speaker.fill").font(.system(size: 11))
                Slider(value: $value, in: 0...100) { isEditing in
                    editing = isEditing
                    if !isEditing { send(now: true) }
                }
                .controlSize(.small)
                .onChange(of: value) { if editing { send(now: false) } }
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            .disabled(!enabled)
            if let caption = model.volumeCaption {
                Text(caption).font(.system(size: 10.5)).foregroundStyle(.tertiary).lineLimit(1)
            } else if hasSource && !enabled {
                Text("Volume controlled on device").font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
        }
        .onAppear { sync() }
        .onChange(of: model.volume) { if !editing { sync() } }
        .accessibilityLabel("Volume")
    }

    private func sync() {
        value = Double(model.volume ?? 50)
    }

    private func send(now: Bool) {
        pending?.cancel()
        let target = Int(value.rounded())
        pending = Task {
            if !now { try? await Task.sleep(for: .milliseconds(150)) }
            guard !Task.isCancelled else { return }
            await model.setVolume(target)
        }
    }
}

struct DeviceChip: View {
    let model: AppModel

    var body: some View {
        if model.store.snapshot != nil || model.airPlayOnly != nil {
            HStack(spacing: 6) {
                Image(systemName: model.routeSymbol).font(.system(size: 11))
                Text(model.routeDisplayName).lineLimit(1)
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.vertical, 4).padding(.leading, 7).padding(.trailing, 9)
            .background(Capsule().fill(.primary.opacity(0.08)))
        }
    }
}

struct OpenSpotifyButton: View {
    let model: AppModel
    var fullWidth = false

    var body: some View {
        Button { model.openSpotify() } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.app.fill").font(.system(size: 13))
                Text("Open Spotify").font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 28)
            .padding(.horizontal, 12)
            .background(Capsule().fill(Color(red: 0x1D / 255, green: 0xB9 / 255, blue: 0x54 / 255)))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

/// What to show instead of the player when signed out, idle or offline.
struct EmptyStateView: View {
    let model: AppModel
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch model.store.phase {
            case .signedOut:
                Text("Not signed in").font(.system(size: 13, weight: .semibold))
                Text(model.clientID.isEmpty ? "Add your Spotify Client ID in Settings, then sign in." : "Sign in with Spotify to see what's playing.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Button(model.clientID.isEmpty ? "Open Settings…" : "Sign in with Spotify…", action: onOpenSettings)
            case .idle:
                Text("Nothing playing").font(.system(size: 13, weight: .semibold))
                Text("Start something on any device, or open Spotify.").font(.system(size: 12)).foregroundStyle(.secondary)
                if let error = model.store.lastError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                }
                OpenSpotifyButton(model: model)
            case .active:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
