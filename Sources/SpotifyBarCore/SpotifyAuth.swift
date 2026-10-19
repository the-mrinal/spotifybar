import Foundation

public enum AuthError: Error, Equatable {
    case notSignedIn
    case invalidGrant
    case keychainUnavailable
    case http(Int)
}

public actor SpotifyAuth {
    public static let redirectURI = "spotifybar://callback"
    public static let scopes = "user-read-playback-state user-modify-playback-state user-read-currently-playing"
    private static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    public typealias HTTP = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let clientID: String
    private let store: TokenStore
    private let http: HTTP
    private let now: @Sendable () -> Date
    private var refreshTask: Task<Tokens, Error>?
    private var cached: Tokens?
    private var generation = 0

    public init(clientID: String, store: TokenStore, http: @escaping HTTP = SpotifyAuth.urlSessionHTTP, now: @escaping @Sendable () -> Date = Date.init) {
        self.clientID = clientID
        self.store = store
        self.http = http
        self.now = now
    }

    public static let urlSessionHTTP: HTTP = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.http(0) }
        return (data, http)
    }

    public var isSignedIn: Bool { (try? currentTokens()) != nil }

    private func currentTokens() throws -> Tokens? {
        if let cached { return cached }
        cached = try store.load()
        return cached
    }

    private func save(_ tokens: Tokens) {
        cached = tokens
        store.save(tokens)
    }

    public func authorizeURL(verifier: String, state: String) -> URL {
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: Self.scopes),
        ]
        return c.url!
    }

    public func exchange(code: String, verifier: String) async throws {
        let tokens = try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ], previousRefresh: nil)
        generation += 1
        save(tokens)
    }

    public func validAccessToken() async throws -> String {
        guard let tokens = try currentTokens() else { throw AuthError.notSignedIn }
        if tokens.expiresAt.timeIntervalSince(now()) > 60 { return tokens.accessToken }
        return try await refresh(tokens).accessToken
    }

    public func forceRefresh() async throws {
        guard let tokens = try currentTokens() else { throw AuthError.notSignedIn }
        _ = try await refresh(tokens)
    }

    public func signOut() {
        refreshTask?.cancel()
        refreshTask = nil
        generation += 1
        cached = nil
        store.clear()
    }

    /// Shares one in-flight refresh between concurrent callers.
    private func refresh(_ tokens: Tokens) async throws -> Tokens {
        if let refreshTask { return try await refreshTask.value }
        let task = Task { [clientID] in
            try await tokenRequest(["grant_type": "refresh_token", "refresh_token": tokens.refreshToken, "client_id": clientID],
                                   previousRefresh: tokens.refreshToken)
        }
        refreshTask = task
        let startedGeneration = generation
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            // A sign-out (or new sign-in) during the refresh wins; don't resurrect old tokens.
            guard generation == startedGeneration else { throw AuthError.notSignedIn }
            save(fresh)
            return fresh
        } catch AuthError.invalidGrant {
            cached = nil
            store.clear()
            throw AuthError.invalidGrant
        }
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
    }

    private func tokenRequest(_ form: [String: String], previousRefresh: String?) async throws -> Tokens {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var c = URLComponents()
        c.queryItems = form.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((c.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await http(request)
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 400,
               let err = try? JSONDecoder().decode([String: String].self, from: data), err["error"] == "invalid_grant" {
                throw AuthError.invalidGrant
            }
            throw AuthError.http(response.statusCode)
        }
        let r = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refresh = r.refresh_token ?? previousRefresh else { throw AuthError.invalidGrant }
        return Tokens(accessToken: r.access_token, refreshToken: refresh, expiresAt: now().addingTimeInterval(TimeInterval(r.expires_in)))
    }
}
