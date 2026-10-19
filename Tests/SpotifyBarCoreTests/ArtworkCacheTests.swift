import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SpotifyBarCore

private func pngData() -> Data {
    let ctx = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return out as Data
}

actor FetchCounter {
    var urls: [URL] = []
    func record(_ u: URL) { urls.append(u) }
}

private func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "artcache-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Suite struct ArtworkCacheTests {
    @Test func cachesInMemoryAndDisk() async throws {
        let dir = tempDir()
        let counter = FetchCounter()
        let png = pngData()
        let cache = ArtworkCache(directory: dir, fetch: { url in await counter.record(url); return png })
        let url = URL(string: "https://i.scdn.co/image/64")!
        let first = await cache.image(for: url)
        let second = await cache.image(for: url)
        #expect(first != nil)
        #expect(second != nil)
        #expect(await counter.urls.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)

        let fresh = ArtworkCache(directory: dir, fetch: { url in await counter.record(url); return png })
        #expect(await fresh.image(for: url) != nil)
        #expect(await counter.urls.count == 1)
    }

    @Test func evictsLRUOverCap() async throws {
        let dir = tempDir()
        let cache = ArtworkCache(directory: dir, maxBytes: 100, fetch: { _ in Data(repeating: 7, count: 60) })
        for i in 0..<3 {
            _ = await cache.image(for: URL(string: "https://x/\(i)")!)
            try await Task.sleep(for: .milliseconds(20))
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.count == 1)
        #expect(files.first == ArtworkCache.fileName(for: URL(string: "https://x/2")!))
    }

    @Test func failedFetchReturnsNil() async {
        struct Boom: Error {}
        let cache = ArtworkCache(directory: tempDir(), fetch: { _ in throw Boom() })
        #expect(await cache.image(for: URL(string: "https://x/y")!) == nil)
    }
}
