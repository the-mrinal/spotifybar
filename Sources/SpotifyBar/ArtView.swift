import SpotifyBarCore
import SwiftUI

/// Album art loaded through the shared cache; shows a neutral tile while loading or when missing.
struct ArtView: View {
    let url: URL?
    let art: ArtworkCache
    var size: CGFloat
    var radius: CGFloat
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                Image(systemName: "music.note").font(.system(size: size * 0.45)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
        .task(id: url) {
            guard let url else { image = nil; return }
            image = await art.image(for: url)
        }
    }
}

/// Single-line text capped at `maxWidth`; when it overflows, the tail fades out instead of an ellipsis.
struct FadingText: View {
    let text: String
    let font: Font
    let maxWidth: CGFloat
    @State private var natural: CGFloat = 0

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { natural = $0 }
            .frame(width: min(natural, maxWidth), alignment: .leading)
            .clipped()
            .mask {
                if natural > maxWidth {
                    LinearGradient(stops: [.init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                } else {
                    Rectangle()
                }
            }
    }
}
