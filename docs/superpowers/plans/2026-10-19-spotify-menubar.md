# SpotifyBar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS menu bar app that shows and controls Spotify playback on any Spotify Connect device.

**Architecture:**
- A Web API client, PKCE auth and a pure-logic `PlaybackStore` and `PollScheduler` form a testable core in a Swift package target.
- A thin AppKit/SwiftUI shell (status item, hover panel, remote panel and settings) observes the store.
- The local Spotify distributed notification only triggers fetches.

**Tech Stack:**
- Swift 6 with SwiftUI and AppKit, targeting macOS 26.
- XcodeGen generates the project.
- Only Apple frameworks are used: URLSession, Security, CryptoKit, AuthenticationServices and ServiceManagement.
- Tests use Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-19-spotify-menubar-design.md`

## Global Constraints

- Deployment target: macOS 26.0; Swift 6 language mode, strict concurrency.
- No third-party dependencies.
- `LSUIElement = YES`; bundle id `dev.mrinal.SpotifyBar`; URL scheme `spotifybar`.
- Redirect URI `spotifybar://callback`. Scopes: `user-read-playback-state user-modify-playback-state user-read-currently-playing`.
- Tokens are stored in the Keychain. The Client ID is stored in UserDefaults under `clientID`.
- No AppleScript, no MediaRemote and no web views (`ASWebAuthenticationSession` is allowed).
- Hover and click must never call `NSApp.activate`. Both panels are non-activating `NSPanel`s.
- The menu bar item never redraws on a timer.
- Polling intervals:

  | State | Interval |
  |---|---|
  | UI visible | 2 s |
  | Playing | 5 s, plus a fetch at the track end + 300 ms |
  | Paused | 15 s |
  | No device | 30 s |
  | Asleep or locked | stopped |

- On a 429 response, honour `Retry-After`. On other errors, back off exponentially to a 60 s maximum.
- Coalesce triggers within 1 s. Event fetches replace the next scheduled poll.
- Bar dimensions:
  - Art is 18 pt with a 4 pt radius.
  - The title is 10.5 pt semibold.
  - Line 2 is 9.5 pt medium in the secondary colour, with a 10 pt device glyph.
  - The text is at most 132 pt wide, and overflow fades out at the right edge.
  - Inline controls appear on hover.
  - When paused, line 2 reads "Paused · <device>".
- Hover card dimensions:
  - It appears after a 350 ms delay and closes after a 250 ms grace period.
  - It is 320 pt wide with a 22 pt radius, over a blurred 64 px art background.
- The remote panel is 304 pt wide with an 18 pt radius.
- Volume slider drags are debounced by 150 ms. Keyboard volume steps are ±10.

## Review Focus

1. **Token expiry while the Mac sleeps overnight.** On wake, the first fetch must refresh silently and must not show the signed-out state. This is tested in Task 3 with `refreshesWhenExpired`.
2. **Spotify returns 204 with an empty body.** This must decode to "nothing playing" and must not throw. Tested in Task 2 with `decodes204AsNil`.
3. **A control fails because the device went away (404 or 403).** The optimistic change must be reverted and an error shown. Tested in Task 4 with `revertsOptimisticToggleOnFailure`.
4. **A track ends while nothing else triggers a fetch.** The track-end fetch must fire so the bar doesn't show a stale track for 5 s. Tested in Task 5 with `schedulesTrackEndFetch`.
5. **A very long title or artist, or CJK or emoji text.** The bar must not exceed 132 pt of text and must not wrap. This is enforced by `.lineLimit(1)` and a frame cap in Task 7, and checked manually in Task 10.

---

## File Structure

```
project.yml                      XcodeGen spec (app target + core framework + tests)
Sources/SpotifyBarCore/          pure logic, no AppKit
  Models.swift                   PlaybackState, Device, Track, DeviceKind, Codable API DTOs
  SpotifyAPI.swift               protocol SpotifyAPIClient + URLSession impl
  PKCE.swift                     verifier/challenge
  TokenStore.swift               Keychain-backed token persistence (protocol + impl)
  SpotifyAuth.swift              authorize URL, code exchange, refresh
  PlaybackStore.swift            @Observable store, merge, optimistic, interpolation, isThisMac
  PollScheduler.swift            interval policy + async loop
  ArtworkCache.swift             memory + disk cache
Sources/SpotifyBar/              app shell
  App.swift                      @main, AppDelegate, Settings scene
  LocalSpotifyObserver.swift     DistributedNotificationCenter + sleep/lock observers
  StatusItemController.swift     NSStatusItem, tracking, right-click menu
  BarView.swift                  D bar SwiftUI view
  HoverCardController.swift      NSPanel + grace timing
  HoverCardView.swift            B card
  RemotePanelController.swift    key-able non-activating NSPanel, outside-click monitor
  RemoteView.swift               D remote
  SettingsView.swift
  DeviceGlyph.swift              DeviceKind → SF Symbol
  Info.plist
Tests/SpotifyBarCoreTests/       Swift Testing + Fixtures/*.json
README.md, THIRD_PARTY_NOTICES (only if code copied), .gitignore
```

---

### Task 1: Scaffold project

**Files:** `project.yml`, `Sources/SpotifyBar/App.swift`, `Sources/SpotifyBar/Info.plist`, `Sources/SpotifyBarCore/Models.swift` (stub), `Tests/SpotifyBarCoreTests/SmokeTests.swift`, `.gitignore`

- [ ] **Step 1:** In `project.yml`, define three targets:
  - `SpotifyBar` (application): Info.plist with `LSUIElement` YES and a `CFBundleURLTypes` entry for scheme `spotifybar`; depends on SpotifyBarCore.
  - `SpotifyBarCore` (framework).
  - `SpotifyBarCoreTests` (unit-test bundle for SpotifyBarCore).

  Shared settings: `SWIFT_VERSION: 6`, `MACOSX_DEPLOYMENT_TARGET: 26.0`, ad-hoc signing (`CODE_SIGN_IDENTITY: "-"`).
- [ ] **Step 2:** Add a minimal `@main struct SpotifyBarApp: App` with an `NSApplicationDelegateAdaptor` and an empty `Settings` scene. Add `.gitignore` entries for `*.xcodeproj` and `build/`.
- [ ] **Step 3:** Run `xcodegen generate && xcodebuild -scheme SpotifyBar -destination 'platform=macOS' -derivedDataPath build test`. It should end with `** TEST SUCCEEDED **`, with one smoke test passing.
- [ ] **Step 4:** Commit: `chore: scaffold XcodeGen project`.

### Task 2: Models and Web API client

**Files:**
- Create: `Sources/SpotifyBarCore/Models.swift`, `Sources/SpotifyBarCore/SpotifyAPI.swift`
- Test: `Tests/SpotifyBarCoreTests/APIDecodingTests.swift`, `Tests/SpotifyBarCoreTests/Fixtures/{track,episode,ad,no_volume}.json`

**Interfaces (produces):**
```swift
public enum DeviceKind: String, Sendable { case computer, smartphone, speaker, tv, avr, stb, audioDongle, gameConsole, castVideo, castAudio, automobile, unknown }
public struct Device: Sendable, Equatable, Identifiable { id: String; name: String; kind: DeviceKind; isActive: Bool; volumePercent: Int?; supportsVolume: Bool }
public struct Track: Sendable, Equatable { id: String; title: String; artist: String; album: String; durationMs: Int; artSmall: URL?; artMedium: URL?; isAd: Bool }
public struct PlayerSnapshot: Sendable, Equatable { track: Track; device: Device; isPlaying: Bool; progressMs: Int; fetchedAt: Date }
public enum SpotifyAPIError: Error, Equatable { case unauthorized, rateLimited(retryAfter: TimeInterval), notFound, forbidden, server(Int), transport }
public protocol SpotifyAPIClient: Sendable {
  func player() async throws -> PlayerSnapshot?          // nil on 204
  func devices() async throws -> [Device]
  func play(deviceID: String?) async throws; func pause() async throws
  func next() async throws; func previous() async throws
  func setVolume(_ percent: Int) async throws
  func transfer(to deviceID: String) async throws
}
public final class URLSessionSpotifyAPI: SpotifyAPIClient  // init(tokenProvider: @Sendable () async throws -> String, session: URLSession = .shared)
public enum PlayerDecoder { static func decode(_ data: Data, status: Int, now: Date) throws -> PlayerSnapshot? }
```

- [ ] **Step 1: Write failing tests.**
  - `decodesTrack`: title, artist, album and device kind `.speaker`. `artSmall` is the 64 px URL and `artMedium` the 300 px URL.
  - `decodesEpisode`: the show name becomes the artist and the show image becomes the art.
  - `decodesAd`: `currently_playing_type: "ad"` gives `isAd == true` and the title "Advertisement".
  - `decodesNoVolume`: `supportsVolume == false`.
  - `decodes204AsNil`.
  - `mapsStatusErrors`: 401 → `.unauthorized`, 429 with `Retry-After: 7` → `.rateLimited(7)`, 404 → `.notFound`.
- [ ] **Step 2:** Run `xcodebuild … test -only-testing:SpotifyBarCoreTests/APIDecodingTests`. It should fail because nothing compiles yet.
- [ ] **Step 3:** Implement the DTOs and `PlayerDecoder`. Then implement `URLSessionSpotifyAPI`:
  - Base URL `https://api.spotify.com/v1`.
  - `player()` calls `GET /me/player?additional_types=episode`.
  - The control endpoints are as listed in the spec. Volume is a `PUT /me/player/volume?volume_percent=N`. Transfer sends the body `{"device_ids":[id],"play":true}`.
  - All non-2xx statuses go through one `mapStatus(_:headers:)`.
- [ ] **Step 4:** Run the tests. They should pass.
- [ ] **Step 5:** Commit: `feat(core): Spotify Web API models and client`.

### Task 3: PKCE, token store and auth

**Files:**
- Create: `Sources/SpotifyBarCore/PKCE.swift`, `Sources/SpotifyBarCore/TokenStore.swift`, `Sources/SpotifyBarCore/SpotifyAuth.swift`
- Test: `Tests/SpotifyBarCoreTests/AuthTests.swift`

**Interfaces (produces):**
```swift
public struct PKCE { static func verifier() -> String /* 64 chars [A-Za-z0-9-._~] */; static func challenge(for verifier: String) -> String /* base64url(SHA256), no padding */ }
public struct Tokens: Codable, Sendable, Equatable { accessToken: String; refreshToken: String; expiresAt: Date }
public protocol TokenStore: Sendable { func load() -> Tokens?; func save(_ t: Tokens); func clear() }
public final class KeychainTokenStore: TokenStore   // service "dev.mrinal.SpotifyBar", account "spotify"
public actor SpotifyAuth {
  init(clientID: String, store: TokenStore, http: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse), now: @Sendable () -> Date = Date.init)
  func authorizeURL(verifier: String, state: String) -> URL
  func exchange(code: String, verifier: String) async throws
  func validAccessToken() async throws -> String   // refreshes if expiresAt - 60s <= now
  func forceRefresh() async throws                 // used on 401
  var isSignedIn: Bool { get }
  func signOut()
}
public enum AuthError: Error { case notSignedIn, invalidGrant }
```

- [ ] **Step 1: Write failing tests.**
  - `challengeMatchesRFC7636Vector`: verifier `dBjftJeZ4CVP-mJ92K27uhbUJU1p1r_wW1gFWFOEjXk` → `E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM`.
  - `authorizeURLHasPKCEParams`: `code_challenge_method=S256`, `redirect_uri=spotifybar://callback`, and the scopes from the global constraints.
  - `refreshesWhenExpired`: with a stub HTTP client and `expiresAt = now + 30`, `validAccessToken()` makes one POST to `https://accounts.spotify.com/api/token` with `grant_type=refresh_token` and saves the new tokens, keeping the old refresh token when the response omits it.
  - `invalidGrantSignsOut`: a 400 `{"error":"invalid_grant"}` throws `.invalidGrant` and clears the store.
- [ ] **Step 2:** Run the tests. They should fail.
- [ ] **Step 3:** Implement. The Keychain store uses `kSecClassGenericPassword` with JSON-encoded `Tokens`. Tests use an in-memory `TokenStore`.
- [ ] **Step 4:** Run the tests. They should pass.
- [ ] **Step 5:** Commit: `feat(core): PKCE auth with keychain tokens`.

### Task 4: PlaybackStore

**Files:**
- Create: `Sources/SpotifyBarCore/PlaybackStore.swift`
- Test: `Tests/SpotifyBarCoreTests/PlaybackStoreTests.swift`

**Interfaces:**
- Consumes: `SpotifyAPIClient`, `PlayerSnapshot`, `Device`, `SpotifyAPIError`.
- Produces:

```swift
public enum PlaybackPhase: Equatable { case signedOut, idle, active(PlayerSnapshot) }
public struct LocalHint: Sendable, Equatable { trackID: String?; isPlaying: Bool; at: Date }  // from com.spotify.client notification
@MainActor @Observable public final class PlaybackStore {
  init(api: SpotifyAPIClient, now: @escaping () -> Date = Date.init, localSpotifyRunning: @escaping () -> Bool)
  private(set) var phase: PlaybackPhase
  private(set) var devices: [Device]
  private(set) var lastError: String?        // cleared on next successful fetch
  private(set) var isStale: Bool             // true when last success > 60 s ago
  var localHint: LocalHint?
  func refresh() async                        // fetch player; updates phase/isStale
  func refreshDevices() async
  func togglePlay() async; func next() async; func previous() async
  func setVolume(_ percent: Int) async        // caller debounces
  func transfer(to: Device) async
  func setSignedOut()
  func progressMs(at: Date) -> Int            // interpolated, clamped to duration
  var isThisMac: Bool { get }                 // spec "Identifying this Mac"
}
```

- [ ] **Step 1: Write failing tests** using a `MockAPI` actor that records calls and returns scripted results.
  - `refreshSetsActive`.
  - `refresh204SetsIdle`.
  - `optimisticToggleFlipsImmediately`: `isPlaying` is false right after a `togglePlay()` that started from playing, before the mock returns.
  - `revertsOptimisticToggleOnFailure`: the mock throws `.notFound`. The phase is reverted to playing and `lastError != nil`.
  - `interpolatesProgress`: progress 10 000 fetched at t0, playing, so at t0+3 s the result is 13 000. It is clamped to the duration and frozen while paused.
  - `isThisMacRequiresAllThree`: type computer, local app running, and the hint matching the track ID and play state gives true. Removing any one of the three gives false.
  - `staleAfter60s`.
- [ ] **Step 2:** Run the tests. They should fail.
- [ ] **Step 3:** Implement it. The previous state is saved before any optimistic mutation and restored in `catch`. `.unauthorized` is handled by the caller (the scheduler wiring in Task 6).
- [ ] **Step 4:** Run the tests. They should pass.
- [ ] **Step 5:** Commit: `feat(core): playback store with optimistic controls`.

### Task 5: PollScheduler

**Files:**
- Create: `Sources/SpotifyBarCore/PollScheduler.swift`
- Test: `Tests/SpotifyBarCoreTests/PollSchedulerTests.swift`

**Interfaces (produces):**
```swift
public struct PollContext: Equatable { var uiVisible: Bool; var phase: PlaybackPhase; var suspended: Bool; var consecutiveErrors: Int; var retryAfter: TimeInterval?; var trackRemainingMs: Int? }
public enum PollPolicy { static func nextDelay(_ c: PollContext) -> TimeInterval? }  // nil = stopped
@MainActor public final class PollScheduler {
  init(policy: @escaping (PollContext) -> TimeInterval? = PollPolicy.nextDelay, context: @escaping () -> PollContext, fetch: @escaping () async -> Void, clock: any Clock<Duration> = ContinuousClock())
  func start(); func stop()
  func trigger()          // event fetch: coalesced within 1 s, replaces next scheduled poll
  func contextChanged()   // re-evaluate delay (UI shown/hidden, sleep/wake)
}
```

- [ ] **Step 1: Write failing tests** for `PollPolicy`.
  - `uiVisibleIs2s`, `playingIs5s`, `pausedIs15s`, `idleIs30s`, `suspendedIsNil`.
  - `schedulesTrackEndFetch`: playing with 1 200 ms remaining gives 1.5 s, the minimum of 5 and 1.2 + 0.3.
  - `honoursRetryAfter`: `retryAfter = 20` gives 20.
  - `backsOffExponentially`: errors 1→10, 2→20, 3→40 and 4→60 (cap) while playing. Use the base interval × 2^n, minimum 10, maximum 60.
- [ ] **Step 2:** Run the tests. They should fail.
- [ ] **Step 3:** Implement the policy and the scheduler:
  - The scheduler runs one `Task` loop: sleep the policy delay, then fetch.
  - `trigger()` cancels the pending sleep and fetches now, unless a fetch started less than 1 s ago. In that case it schedules a fetch for 1 s after the last one.
  - Add a test `triggerCoalescesWithin1s` that uses a test clock or short real delays and counts fetches.
- [ ] **Step 4:** Run the tests. They should pass.
- [ ] **Step 5:** Commit: `feat(core): adaptive poll scheduler`.

### Task 6: Artwork cache and app wiring

**Files:**
- Create: `Sources/SpotifyBarCore/ArtworkCache.swift`, `Sources/SpotifyBar/LocalSpotifyObserver.swift`, `Sources/SpotifyBar/AppModel.swift`
- Test: `Tests/SpotifyBarCoreTests/ArtworkCacheTests.swift`

**Interfaces (produces):**
```swift
public actor ArtworkCache { init(directory: URL, maxBytes: Int = 50_000_000, fetch: @Sendable (URL) async throws -> Data = default); func image(for url: URL) async -> CGImage? }
@MainActor final class AppModel { let store: PlaybackStore; let auth: SpotifyAuth?; let scheduler: PollScheduler; let art: ArtworkCache
  var uiVisible: Bool { didSet { scheduler.contextChanged() } }
  func signIn(anchor: ASPresentationAnchor) async throws; func signOut()
  func openSpotify() }
```

- [ ] **Step 1: Write failing tests.**
  - `cachesInMemoryAndDisk`: a second call doesn't fetch again, and the file exists on disk.
  - `evictsLRUOverCap`: with a 100-byte cap and three 60-byte images, the oldest file is removed.
- [ ] **Step 2:** Run the tests. They should fail. Then implement, decoding with `CGImageSource`. Run them again; they should pass.
- [ ] **Step 3:** Implement `LocalSpotifyObserver`. It observes:
  - `com.spotify.client.PlaybackStateChanged`. It reads `Track ID` (`spotify:track:<id>` → `<id>`) and `Player State`, sets `store.localHint` and calls `scheduler.trigger()`.
  - `NSWorkspace.willSleep/didWake/screensDidSleep/screensDidWake` and the distributed notifications `com.apple.screenIsLocked/Unlocked`. These toggle `suspended`, and waking triggers a fetch.
- [ ] **Step 4:** Implement `AppModel`:
  - It wires the API token provider to `auth.validAccessToken()`.
  - On `.unauthorized` it calls `auth.forceRefresh()` and retries once. On `invalidGrant` it calls `store.setSignedOut()`.
  - Sign-in uses `ASWebAuthenticationSession(url:callback: .customScheme("spotifybar"))` with `prefersEphemeralWebBrowserSession = false`.
  - `openSpotify()` opens the bundle `com.spotify.client` through `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`, falling back to `https://open.spotify.com`.
- [ ] **Step 5:** Build. It should end with `** BUILD SUCCEEDED **`. Commit: `feat: artwork cache and app model wiring`.

### Task 7: Menu bar item (D)

**Files:**
- Create: `Sources/SpotifyBar/StatusItemController.swift`, `Sources/SpotifyBar/BarView.swift`, `Sources/SpotifyBar/DeviceGlyph.swift`

**Interfaces (produces):**
```swift
@MainActor final class StatusItemController: NSObject {
  init(model: AppModel)
  var onHoverChanged: (Bool) -> Void
  var onClick: () -> Void
  var buttonFrameInScreen: NSRect { get }
}
func deviceSymbol(_ k: DeviceKind) -> String
// computer→"laptopcomputer", smartphone→"iphone", speaker→"hifispeaker", tv/castVideo/stb→"tv", automobile→"car", avr/castAudio/audioDongle→"hifispeaker.2", gameConsole→"gamecontroller", unknown→"speaker.wave.2"
```

- [ ] **Step 1:** Implement `BarView(store:, art:, hovering:)` using the bar dimensions from the global constraints.
  - Both lines use `.lineLimit(1)`, and the text uses `.frame(maxWidth: 132, alignment: .leading)`. The overflow fade is a `.mask` linear gradient applied only when the text is truncated, detected by comparing a measured width with 132.
  - The inline prev/play/next buttons are 16 pt SF Symbols in an `HStack`, shown when `hovering`. The animation is `.snappy` unless `accessibilityReduceMotion` is on.
  - The idle and signed-out states show `music.note`, which is dimmed when idle.
  - Use `.foregroundStyle(.primary/.secondary)` so the item follows the menu bar's light or dark appearance.
- [ ] **Step 2:** Implement `StatusItemController`:
  - Create an `NSStatusItem(variableLength)` whose button gets an `NSHostingView` subview pinned to its edges.
  - Set `hostingView.sizingOptions = [.intrinsicContentSize]` and update `statusItem.length` from `fittingSize` whenever the track, play state, device or hover state changes. Never update it from a timer.
  - Add an `NSTrackingArea` with `.mouseEnteredAndExited, .activeAlways`.
  - Left-click goes to `onClick`. Right-click shows an `NSMenu` with Settings…, Sign Out and Quit, using `statusItem.menu` only for that click and resetting it afterwards.
  - Set an accessibility label: "Now playing: <title> by <artist> on <device>".
- [ ] **Step 3:** Run the app with `xcodegen generate && xcodebuild -scheme SpotifyBar -derivedDataPath build build && open build/Build/Products/Debug/SpotifyBar.app`. The music-note glyph should appear in the menu bar. Commit: `feat: stacked ticker status item`.

### Task 8: Hover card (B)

**Files:**
- Create: `Sources/SpotifyBar/HoverCardController.swift`, `Sources/SpotifyBar/HoverCardView.swift`

**Interfaces:**
- Consumes: `StatusItemController.onHoverChanged` and `buttonFrameInScreen`, plus `AppModel`.
- Produces: `HoverCardController(model:)` with `itemHover(_ inside: Bool)`, `suppress(_ on: Bool)`.

- [ ] **Step 1:** Create an `NSPanel` with:
  - styleMask `[.nonactivatingPanel, .borderless]`, `level = .statusBar`, `isFloatingPanel = true` and `hidesOnDeactivate = false`;
  - `canBecomeKey` and `canBecomeMain` overridden to return false;
  - `backgroundColor = .clear` and `hasShadow = true`.

  Position it 6 pt below the item, with its centre aligned to the item and clamped to the screen's `visibleFrame`.
- [ ] **Step 2:** Implement the hover timing:
  - Hovering over the item starts a 350 ms show timer.
  - Leaving the item or the card starts a 250 ms hide timer.
  - Entering the card cancels the hide timer (use the card's own tracking area).
  - Showing sets `model.uiVisible = true` and hiding sets it to false.
- [ ] **Step 3:** Build `HoverCardView`:
  - 320 pt wide with a 22 pt radius.
  - Background: the 64 px art blurred with `.blur(radius: 36)` and `.saturation(1.5)`, under `.glassEffect(.regular, in: .rect(cornerRadius: 22))`. Under Reduce Transparency, use `.background(.regularMaterial)` instead.
  - 72 pt art, then title, artist, album and a device chip.
  - A progress bar driven by `TimelineView(.periodic(by: 1))` using `store.progressMs(at:)`.
  - Prev, play and next buttons and a volume `Slider`. The slider debounces with `Task.sleep(150 ms)` cancellation and sends the final value on release.
  - Signed-out, idle and offline variants as in the spec's edge-state table.
- [ ] **Step 3b:** Wire the card to `suppress(true)` while the remote panel is open.
- [ ] **Step 4:** Build and run. Hovering should show the card after about 350 ms, and the app you're working in should keep focus (check the frontmost app's menu bar name). Commit: `feat: glass hover card`.

### Task 9: Remote panel (D) and Settings

**Files:**
- Create: `Sources/SpotifyBar/RemotePanelController.swift`, `Sources/SpotifyBar/RemoteView.swift`, `Sources/SpotifyBar/SettingsView.swift`
- Modify: `Sources/SpotifyBar/App.swift`

- [ ] **Step 1:** Create the remote panel:
  - An `NSPanel` subclass with `[.nonactivatingPanel, .borderless]`, `canBecomeKey` overridden to return true, and `.statusBar` level.
  - `toggle()` positions it under the item and calls `makeKeyAndOrderFront(nil)`. It must **not** call `NSApp.activate`.
  - Use `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])` to close it on an outside click.
  - A local key monitor handles Esc (close), Space (togglePlay), ← and → (previous/next), and ↑ and ↓ (±10 volume).
  - Opening it sets `uiVisible`, calls `store.refreshDevices()`, and refreshes the devices every 10 s while it is open.
- [ ] **Step 2:** Build `RemoteView`:
  - 304 pt wide with an 18 pt radius and glass.
  - Header: a 38 pt device icon tile and "Playing on <name>", or "This Mac" when `isThisMac`.
  - A now-playing row and the volume slider. The slider is disabled when `!supportsVolume`, with the hint "Volume controlled on device".
  - A "Switch to" list of inactive devices, which calls `store.transfer`.
  - A full-width green "Open Spotify" button using Spotify green `#1DB954` and black text.
- [ ] **Step 3:** Build `SettingsView`, opened via `openSettings` from the right-click menu:
  - A Client ID field and a Sign In / Sign Out button.
  - A short "How to get a Client ID" text with the redirect URI to copy.
  - A launch-at-login `Toggle` backed by `SMAppService.mainApp.register()` / `unregister()`.
  - A "Show artist line" toggle (`@AppStorage("showArtist")`, default true).
  - A max title width stepper (`@AppStorage("maxTitleWidth")`, default 132, range 80–200), read by BarView.
- [ ] **Step 4:** Run it and sign in with a real Client ID:
  - The bar should show the track playing on your phone.
  - Clicking should open the remote, and the frontmost app shouldn't change.
  - Esc should close it.
  - Switching device should work.

  Commit: `feat: device remote panel and settings`.

### Task 10: README, verification and release

**Files:** `README.md`, optionally `THIRD_PARTY_NOTICES`, `scripts/build-release.sh`

- [ ] **Step 1:** Write the README: what it does, a screenshot placeholder, the Spotify app setup (dashboard → create app → redirect URI `spotifybar://callback` → Web API → copy the Client ID), the build steps, and the privacy note that tokens are kept in the Keychain and the app talks only to Spotify.
- [ ] **Step 2:** Write `scripts/build-release.sh`. It should run `xcodegen generate`, `xcodebuild -configuration Release`, `ditto -c -k --keepParent SpotifyBar.app SpotifyBar.zip`.
- [ ] **Step 3:** Run the full test suite. It should end with `** TEST SUCCEEDED **`.
- [ ] **Step 4:** Check performance while playing with no UI open:
  - `top -l 6 -s 10 -pid $(pgrep SpotifyBar) -stats cpu,mem` should average under 0.5% CPU and under 40 MB of memory.
  - Long titles, CJK text and emoji shouldn't overflow the bar.
- [ ] **Step 5:** Commit: `docs: README and release script`. Then create the GitHub repo, push, and create a release with the zip.
