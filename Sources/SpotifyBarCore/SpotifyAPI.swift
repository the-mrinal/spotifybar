import Foundation

public enum SpotifyAPIError: Error, Equatable, Sendable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval)
    case notFound
    case forbidden
    case server(Int)
    case transport

    public static func map(status: Int, headers: [String: String]) -> SpotifyAPIError {
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 429:
            let value = headers.first { $0.key.caseInsensitiveCompare("Retry-After") == .orderedSame }?.value
            return .rateLimited(retryAfter: value.flatMap(TimeInterval.init) ?? 5)
        default: return .server(status)
        }
    }
}

public protocol SpotifyAPIClient: Sendable {
    func player() async throws -> PlayerSnapshot?
    func devices() async throws -> [Device]
    func play(deviceID: String?) async throws
    func pause() async throws
    func next() async throws
    func previous() async throws
    func setVolume(_ percent: Int) async throws
    func transfer(to deviceID: String) async throws
}

public final class URLSessionSpotifyAPI: SpotifyAPIClient {
    private let base = URL(string: "https://api.spotify.com/v1")!
    private let tokenProvider: @Sendable () async throws -> String
    private let session: URLSession

    public init(tokenProvider: @escaping @Sendable () async throws -> String, session: URLSession = .shared) {
        self.tokenProvider = tokenProvider
        self.session = session
    }

    public func player() async throws -> PlayerSnapshot? {
        let (data, status) = try await send("GET", "/me/player", query: [URLQueryItem(name: "additional_types", value: "episode")])
        return try PlayerDecoder.decode(data, status: status, now: Date())
    }

    public func devices() async throws -> [Device] {
        let (data, _) = try await send("GET", "/me/player/devices")
        return try PlayerDecoder.decodeDevices(data)
    }

    public func play(deviceID: String?) async throws {
        let query = deviceID.map { [URLQueryItem(name: "device_id", value: $0)] } ?? []
        _ = try await send("PUT", "/me/player/play", query: query)
    }

    public func pause() async throws { _ = try await send("PUT", "/me/player/pause") }
    public func next() async throws { _ = try await send("POST", "/me/player/next") }
    public func previous() async throws { _ = try await send("POST", "/me/player/previous") }

    public func setVolume(_ percent: Int) async throws {
        let clamped = min(100, max(0, percent))
        _ = try await send("PUT", "/me/player/volume", query: [URLQueryItem(name: "volume_percent", value: String(clamped))])
    }

    public func transfer(to deviceID: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["device_ids": [deviceID], "play": true])
        _ = try await send("PUT", "/me/player", body: body)
    }

    private func send(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> (Data, Int) {
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if method != "GET" {
            request.setValue("0", forHTTPHeaderField: "Content-Length")
        }

        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch { throw SpotifyAPIError.transport }
        guard let http = response as? HTTPURLResponse else { throw SpotifyAPIError.transport }
        guard (200..<300).contains(http.statusCode) else {
            let headers = http.allHeaderFields.reduce(into: [String: String]()) { $0["\($1.key)"] = "\($1.value)" }
            throw SpotifyAPIError.map(status: http.statusCode, headers: headers)
        }
        return (data, http.statusCode)
    }
}
