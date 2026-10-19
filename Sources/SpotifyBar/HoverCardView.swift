import SpotifyBarCore
import SwiftUI

/// Design B "Glass Stage": art-tinted glass card with inline transport and volume.
struct HoverCardView: View {
    let model: AppModel
    var onOpenSettings: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var store: PlaybackStore { model.store }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let airplay = model.airPlayOnly {
                AirPlayNowPlaying(model: model, airplay: airplay, artSize: 96)
                chipRow
                VolumeRow(model: model)
            } else if let s = store.snapshot {
                HStack(alignment: .top, spacing: 13) {
                    ArtView(url: s.track.artMedium, art: model.art, size: 96, radius: 10)
                        .shadow(color: .black.opacity(0.45), radius: 9, y: 6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.track.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                        Text(s.track.artist).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        Text(s.track.album).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        chipRow.padding(.top, 8)
                    }
                    .padding(.top, 4)
                }
                ProgressRow(store: store)
                TransportRow(store: store)
                VolumeRow(model: model)
                if let error = store.lastError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                } else if store.isStale {
                    Text("Offline — showing last known state").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else {
                EmptyStateView(model: model, onOpenSettings: onOpenSettings)
            }
        }
        .padding(14)
        .frame(width: 320)
        .background { background }
        .clipShape(.rect(cornerRadius: 22))
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            DeviceChip(model: model)
            BatteryBadge(speaker: model.speaker)
        }
    }

    private var artURL: URL? {
        model.airPlayOnly != nil ? model.speaker.coverURL() : store.snapshot?.track.artSmall
    }

    @ViewBuilder private var background: some View {
        if reduceTransparency {
            Rectangle().fill(.regularMaterial)
        } else {
            ZStack {
                if let url = artURL {
                    ArtView(url: url, art: model.art, size: 400, radius: 0)
                        .blur(radius: 36)
                        .saturation(1.5)
                        .opacity(0.95)
                }
                Rectangle().fill(.clear).glassEffect(.regular, in: .rect(cornerRadius: 22))
            }
        }
    }
}
