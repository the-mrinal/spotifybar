import Foundation
import Testing
@testable import SpotifyBarCore

final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: Tokens?
    init(_ tokens: Tokens? = nil) { self.tokens = tokens }
    func load() -> Tokens? { lock.withLock { tokens } }
    func save(_ t: Tokens) { lock.withLock { tokens = t } }
    func clear() { lock.withLock { tokens = nil } }
}

actor RecordingHTTP {
    var requests: [URLRequest] = []
    let status: Int
    let body: String
    init(status: Int, body: String) { self.status = status; self.body = body }
    func handle(_ r: URLRequest) -> (Data, HTTPURLResponse) {
        requests.append(r)
        return (Data(body.utf8), HTTPURLResponse(url: r.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private let t0 = Date(timeIntervalSince1970: 2_000_000)

@Suite struct AuthTests {
    @Test func challengeMatchesRFC7636Vector() {
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func verifierIs64UnreservedChars() {
        let v = PKCE.verifier()
        #expect(v.count == 64)
        #expect(v.allSatisfy { $0.isLetter || $0.isNumber || "-._~".contains($0) })
    }

    @Test func authorizeURLHasPKCEParams() async {
        let http = RecordingHTTP(status: 200, body: "{}")
        let auth = SpotifyAuth(clientID: "cid", store: MemoryTokenStore(), http: { await http.handle($0) }, now: { t0 })
        let url = await auth.authorizeURL(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "st")
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        #expect(url.host() == "accounts.spotify.com")
        #expect(items["client_id"] == "cid")
        #expect(items["response_type"] == "code")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["code_challenge"] == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(items["redirect_uri"] == "spotifybar://callback")
        #expect(items["state"] == "st")
        #expect(items["scope"] == "user-read-playback-state user-modify-playback-state user-read-currently-playing")
    }

    @Test func exchangeStoresTokens() async throws {
        let http = RecordingHTTP(status: 200, body: #"{"access_token":"A1","refresh_token":"R1","expires_in":3600,"token_type":"Bearer"}"#)
        let store = MemoryTokenStore()
        let auth = SpotifyAuth(clientID: "cid", store: store, http: { await http.handle($0) }, now: { t0 })
        try await auth.exchange(code: "c0de", verifier: "v")
        #expect(store.load() == Tokens(accessToken: "A1", refreshToken: "R1", expiresAt: t0.addingTimeInterval(3600)))
        let body = String(decoding: await http.requests[0].httpBody!, as: UTF8.self)
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code_verifier=v"))
        #expect(await auth.isSignedIn)
    }

    @Test func validTokenSkipsRefreshWhenFresh() async throws {
        let http = RecordingHTTP(status: 200, body: "{}")
        let store = MemoryTokenStore(Tokens(accessToken: "OLD", refreshToken: "R0", expiresAt: t0.addingTimeInterval(600)))
        let auth = SpotifyAuth(clientID: "cid", store: store, http: { await http.handle($0) }, now: { t0 })
        #expect(try await auth.validAccessToken() == "OLD")
        #expect(await http.requests.isEmpty)
    }

    @Test func refreshesWhenExpired() async throws {
        let http = RecordingHTTP(status: 200, body: #"{"access_token":"NEW","expires_in":3600,"token_type":"Bearer"}"#)
        let store = MemoryTokenStore(Tokens(accessToken: "OLD", refreshToken: "R0", expiresAt: t0.addingTimeInterval(30)))
        let auth = SpotifyAuth(clientID: "cid", store: store, http: { await http.handle($0) }, now: { t0 })
        #expect(try await auth.validAccessToken() == "NEW")
        let reqs = await http.requests
        #expect(reqs.count == 1)
        #expect(reqs[0].url?.absoluteString == "https://accounts.spotify.com/api/token")
        #expect(reqs[0].httpMethod == "POST")
        #expect(String(decoding: reqs[0].httpBody!, as: UTF8.self).contains("grant_type=refresh_token"))
        #expect(store.load() == Tokens(accessToken: "NEW", refreshToken: "R0", expiresAt: t0.addingTimeInterval(3600)))
    }

    @Test func invalidGrantSignsOut() async {
        let http = RecordingHTTP(status: 400, body: #"{"error":"invalid_grant"}"#)
        let store = MemoryTokenStore(Tokens(accessToken: "OLD", refreshToken: "R0", expiresAt: t0))
        let auth = SpotifyAuth(clientID: "cid", store: store, http: { await http.handle($0) }, now: { t0 })
        await #expect(throws: AuthError.invalidGrant) { try await auth.validAccessToken() }
        #expect(store.load() == nil)
        #expect(await auth.isSignedIn == false)
    }

    @Test func notSignedInThrows() async {
        let http = RecordingHTTP(status: 200, body: "{}")
        let auth = SpotifyAuth(clientID: "cid", store: MemoryTokenStore(), http: { await http.handle($0) }, now: { t0 })
        await #expect(throws: AuthError.notSignedIn) { try await auth.validAccessToken() }
    }
}
