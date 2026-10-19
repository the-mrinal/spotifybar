import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// Album art cache: decoded images in memory, raw bytes on disk with LRU eviction.
public actor ArtworkCache {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    private let directory: URL
    private let maxBytes: Int
    private let fetch: Fetch
    private var memory: [URL: CGImage] = [:]
    private var memoryOrder: [URL] = []
    private let memoryLimit = 24

    public init(directory: URL, maxBytes: Int = 50_000_000, fetch: @escaping Fetch = ArtworkCache.urlSessionFetch) {
        self.directory = directory
        self.maxBytes = maxBytes
        self.fetch = fetch
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public static let urlSessionFetch: Fetch = { url in try await URLSession.shared.data(from: url).0 }

    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "dev.mrinal.SpotifyBar/art", directoryHint: .isDirectory)
    }

    static func fileName(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public func image(for url: URL) async -> CGImage? {
        if let hit = memory[url] {
            touchMemory(url)
            return hit
        }
        let file = directory.appending(path: Self.fileName(for: url))
        let data: Data
        if let cached = try? Data(contentsOf: file) {
            data = cached
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        } else {
            guard let fetched = try? await fetch(url) else { return nil }
            data = fetched
            try? fetched.write(to: file, options: .atomic)
            evictIfNeeded()
        }
        guard let image = Self.decode(data) else { return nil }
        memory[url] = image
        touchMemory(url)
        return image
    }

    private func touchMemory(_ url: URL) {
        memoryOrder.removeAll { $0 == url }
        memoryOrder.append(url)
        while memoryOrder.count > memoryLimit {
            memory[memoryOrder.removeFirst()] = nil
        }
    }

    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    private func evictIfNeeded() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        var entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.1 }
        guard total > maxBytes else { return }
        entries.sort { $0.2 < $1.2 }
        for (url, size, _) in entries where total > maxBytes {
            try? FileManager.default.removeItem(at: url)
            total -= size
        }
    }
}
