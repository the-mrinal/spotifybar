import SpotifyBarCore
import SwiftUI

@MainActor @Observable
final class BarState {
    var hovering = false
    var highlighted = false
}

/// Design D "Stacked Ticker": 18 pt art, title over artist, inline transport on hover.
struct BarView: View {
    let model: AppModel
    let state: BarState
    var onClick: () -> Void
    var onWidth: (CGFloat) -> Void

    @AppStorage("maxTitleWidth") private var maxTitleWidth = 132.0
    @AppStorage("showArtist") private var showArtist = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: PlaybackStore { model.store }

    var body: some View {
        HStack(spacing: 6) {
            content
            if state.hovering, let s = store.snapshot {
                inlineControls(isPlaying: s.isPlaying)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(.primary.opacity(state.highlighted ? 0.16 : (state.hovering ? 0.08 : 0)))
        }
        .contentShape(.rect)
        .onTapGesture(perform: onClick)
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { onWidth($0) }
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: state.hovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .signedOut, .idle:
            Image(systemName: "music.note")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(store.phase == .idle ? .secondary : .primary)
                .frame(width: 18, height: 18)
        case .active(let s):
            ZStack {
                ArtView(url: s.track.artSmall, art: model.art, size: 18, radius: 4)
                    .grayscale(s.isPlaying ? 0 : 1)
                    .opacity(s.isPlaying ? 1 : 0.45)
                if !s.isPlaying {
                    Image(systemName: "pause.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                FadingText(text: s.track.title, font: .system(size: 10.5, weight: .semibold), maxWidth: maxTitleWidth)
                HStack(spacing: 3) {
                    Image(systemName: s.isPlaying ? deviceSymbol(s.device.kind) : "pause.fill")
                        .font(.system(size: 8.5, weight: .medium))
                        .frame(width: 10, height: 10)
                    FadingText(text: secondLine(s), font: .system(size: 9.5, weight: .medium), maxWidth: maxTitleWidth - 13)
                }
                .foregroundStyle(.secondary)
            }
            .foregroundStyle(s.isPlaying ? .primary : .secondary)
            .opacity(store.isStale ? 0.55 : 1)
        }
    }

    private func secondLine(_ s: PlayerSnapshot) -> String {
        if !s.isPlaying { return "Paused · \(store.deviceDisplayName)" }
        return showArtist ? s.track.artist : store.deviceDisplayName
    }

    private func inlineControls(isPlaying: Bool) -> some View {
        HStack(spacing: 0) {
            BarButton(symbol: "backward.fill", label: "Previous track") { Task { await store.previous() } }
            BarButton(symbol: isPlaying ? "pause.fill" : "play.fill", label: isPlaying ? "Pause" : "Play") { Task { await store.togglePlay() } }
            BarButton(symbol: "forward.fill", label: "Next track") { Task { await store.next() } }
        }
        .padding(.leading, 2)
    }

    private var accessibilityText: String {
        switch store.phase {
        case .signedOut: "Spotify: signed out"
        case .idle: "Spotify: nothing playing"
        case .active(let s): "Now playing: \(s.track.title) by \(s.track.artist) on \(store.deviceDisplayName)"
        }
    }
}

private struct BarButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(hover ? 0.14 : 0)))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(label)
    }
}
