import SpotifyBarCore
import SwiftUI

/// Design D "Device Remote": organised around the device that's playing.
struct RemoteView: View {
    let model: AppModel
    var onOpenSettings: () -> Void

    private var store: PlaybackStore { model.store }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let s = store.snapshot {
                header(s)
                nowPlaying(s)
                ProgressRow(store: store)
                TransportRow(store: store)
                VolumeRow(store: store)
                if let error = store.lastError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                }
            } else {
                EmptyStateView(model: model, onOpenSettings: onOpenSettings)
            }
            if store.phase != .signedOut {
                switchList
                OpenSpotifyButton(model: model, fullWidth: true)
            }
        }
        .padding(14)
        .frame(width: 304)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func header(_ s: PlayerSnapshot) -> some View {
        HStack(spacing: 11) {
            Image(systemName: deviceSymbol(s.device.kind))
                .font(.system(size: 20))
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.08)))
            VStack(alignment: .leading, spacing: 1) {
                Text("PLAYING ON").font(.system(size: 10, weight: .semibold)).kerning(0.6).foregroundStyle(.tertiary)
                Text(store.deviceDisplayName).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            }
        }
    }

    private func nowPlaying(_ s: PlayerSnapshot) -> some View {
        HStack(spacing: 10) {
            ArtView(url: s.track.artMedium, art: model.art, size: 44, radius: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.track.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(s.track.album.isEmpty ? s.track.artist : "\(s.track.artist) · \(s.track.album)")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(0.06)))
    }

    @ViewBuilder private var switchList: some View {
        let others = store.devices.filter { $0.id != store.snapshot?.device.id }
        if !others.isEmpty {
            Divider().padding(.vertical, 2)
            Text(store.snapshot == nil ? "PLAY ON" : "SWITCH TO")
                .font(.system(size: 10, weight: .semibold)).kerning(0.6).foregroundStyle(.tertiary)
            VStack(spacing: 1) {
                ForEach(others) { device in
                    DeviceRow(device: device) { Task { await store.transfer(to: device) } }
                }
            }
            .padding(.horizontal, -6)
        }
    }
}

private struct DeviceRow: View {
    let device: Device
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: deviceSymbol(device.kind)).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 16)
                Text(device.name).font(.system(size: 13)).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(hover ? 0.08 : 0)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel("Play on \(device.name)")
    }
}
