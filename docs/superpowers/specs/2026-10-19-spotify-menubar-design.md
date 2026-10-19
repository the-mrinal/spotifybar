# Spotify Menu Bar Now Playing — Design

Date: 2026-10-19
Status: draft, awaiting approval

Items marked *Claude's call* were decided by Claude, not Mrinal.

## Intent

While working, Mrinal glances at the macOS menu bar to see what song is
playing, and occasionally wants to change volume, play/pause, skip, or jump
to the Spotify app, without switching windows.

The key twist: playback is often **not on this Mac**. It may be on a phone,
smart speaker or TV via Spotify Connect. The menu bar must show and control
whatever Spotify is playing on the account, wherever it is playing.

Everything must feel native, fast and light.

## Goals

- Show the current track in the menu bar: a small album art thumbnail plus
  title and artist.
- Show which device is playing when it isn't this Mac.
- Show a rich hover card on hover, with no click needed: large art, title,
  artist, album, progress, device, and transport and volume controls.
- On click, open a device-centric remote: playing device, device volume,
  switch device, and Open Spotify.
- Controls: play/pause, previous/next, volume up and down, open the Spotify
  app.
- Work for playback on any Spotify Connect device on the account.

## Non-goals (v1)

- Lyrics, liking or saving tracks, search, queue, playlists or browsing.
- Apple Music or other players.
- Global keyboard shortcuts.
- Track-change notifications.
- Multiple Spotify accounts.
- Distribution to other users. This is a personal app; the Spotify dev-mode
  cap of 5 users is fine.

## Anti-goals (a failure even if it works)

- Electron, web views or any embedded browser UI, apart from the system
  OAuth sheet.
- Noticeable CPU or battery use. A menu bar app that shows up in Activity
  Monitor is a failure.
- Stealing focus from the app Mrinal is working in. Hover must never
  activate our app.
- A Dock icon or app switcher entry.
- Spamming the Spotify API until it gets rate-limited.

## Decisions already made

### Build vs fork

**Build in-house.** *Claude's call.*

Research on 2026-10-19 found no open-source app that shows remote Spotify
Connect playback. They all read the local Spotify client via AppleScript or
MediaRemote. The closest base, [SpotMenu](https://github.com/kmikiy/SpotMenu)
(MIT), only puts text in the bar and only reads local playback, so the two
core features would be new code anyway.

SpotMenu's PKCE auth code (`SpotifyAuthManager.swift`) may be used as a
reference or adapted. It is MIT-licensed, so keep its copyright notice in a
`THIRD_PARTY_NOTICES` file if any code is copied. Do **not** copy from
`m2nwo079/spotify-menubar-remote`, which has no license.

### Account prerequisites (confirmed by Mrinal)

- Mrinal has Spotify Premium, which Spotify's player-control endpoints require.
- Mrinal will create a Spotify developer app to get a Client ID.

### Chosen visual design

The design came from Open Design. Reference files are in `docs/design/`:

- `alternatives.html` shows the four original options, A to D.
- `mix-and-match.html` is the configurator Mrinal used to pick the combination.

The selection code was:
`BAR=D HOVER=B CLICK=D artist=on width=132 shape=rounded device=on`

Treat the HTML as the visual source of truth for spacing, type sizes, radii
and colours. The sections below summarise it.

#### Menu bar item: "Stacked Ticker" (D)

- Left to right: an **18 pt album art** thumbnail with a rounded square corner
  (~4 pt radius), then a two-line text stack.
  - Line 1 is the **title**: SF Pro 10.5 pt semibold.
  - Line 2 is the **artist**: 9.5 pt medium, secondary label colour. It is
    always prefixed with a 10 pt **device glyph** for the active device (TV,
    speaker, phone, laptop for this Mac, car and so on). This matches the
    configurator with `device=on`.
- The text stack has a **maximum width of 132 pt**. Overflow fades out at the
  right edge with a gradient mask. There is no marquee or scrolling.
- **Paused:** the text is dimmed and line 2 becomes "⏸ Paused · <short
  device name>", matching `mix-and-match.html`'s D bar renderer. The title
  stays on line 1.
- **Hover:** the item animates wider to reveal inline **previous / play-pause /
  next** buttons in the bar itself, roughly +68 pt. They collapse again when
  the pointer leaves.
- **Nothing playing, signed out or offline:** show only a template music-note
  glyph at 16 pt. See the edge states below.
- The item follows the light/dark menu bar appearance automatically.

#### Hover card: "Glass Stage" (B)

- Appears ~350 ms after the pointer rests on the menu bar item, with no click.
- Stays open while the pointer moves from the item into the card. It closes
  ~250 ms after the pointer leaves both.
- 320 pt wide with a 22 pt corner radius. The background is a heavily blurred
  copy of the album art under a Liquid Glass material.
- Contents:
  - ~72 pt album art.
  - Title, artist and album.
  - A device chip showing the icon and device name.
  - A progress bar with elapsed and total time.
  - Previous / play-pause / next controls.
  - A volume slider.
- The controls work directly in the card, so one click on the card skips a
  track.
- The card is suppressed while the click popover is open.

#### Click popover: "Device Remote" (D)

- 304 pt wide with an 18 pt corner radius.
- Contents:
  - A header with a large device icon and "Playing on <device name>".
  - A compact now-playing row: art, title and artist.
  - The device's volume slider. It is disabled with a hint when the device
    reports `supports_volume = false`.
  - A "Switch to" list of the account's other available devices. Clicking one
    transfers playback there.
  - A full-width green **Open Spotify** button.
- Esc or a click outside closes it.
- Keyboard while the popover is open:
  - Space plays or pauses.
  - ← and → go to the previous and next track.
  - ↑ and ↓ change the volume in ±10 steps.

#### Right-click menu on the item

A standard NSMenu with Settings…, Sign Out and Quit.

## Technical decisions (frozen)

### Platform and stack

- **macOS 26 minimum deployment target.** This allows SwiftUI
  `.glassEffect()` and Liquid Glass. Mrinal runs macOS 27.2 with Xcode 27.
- **Swift 6** with strict concurrency. Use **SwiftUI** for all views and
  **AppKit** for the status item, panels and popover.
- **No third-party dependencies.** Use only URLSession, Security (Keychain),
  CryptoKit (PKCE), AuthenticationServices (ASWebAuthenticationSession) and
  ServiceManagement (launch at login).
- **XcodeGen** (`project.yml`, installed at `/opt/homebrew/bin/xcodegen`)
  generates the Xcode project. The `.xcodeproj` is git-ignored.
- `LSUIElement = YES`, so the app has no Dock icon or app switcher entry.
- The bundle ID is `dev.mrinal.SpotifyBar`. The product name is a placeholder,
  "SpotifyBar", and the builder may rename it. Avoid using "Spotify" alone as
  the display name, because of Spotify's trademark.

### Data sources

Two sources are merged into one `PlaybackState`.

1. **Spotify Web API** (`GET https://api.spotify.com/v1/me/player`) is the
   source of truth. It covers any device and provides the device name, type
   and volume, album images, progress, `is_playing` and `supports_volume`.
2. **The local Spotify client's distributed notification**
   (`com.spotify.client.PlaybackStateChanged` via
   `DistributedNotificationCenter`). It is free and instant, and needs no
   permission prompt. It is used **only as a trigger**: when it fires, fetch
   `/me/player` immediately. That makes changes on this Mac appear instantly
   without fast polling. Its own payload (name, artist, state) may be shown
   optimistically until the fetch returns.

- **No AppleScript.** It would add an Automation permission prompt and isn't
  needed.
- **No MediaRemote.** It is private, broken for third-party apps since macOS
  15.4, and local-only.

### Polling schedule

Polling is adaptive and runs on a single scheduler, never multiple timers.

| State | Interval |
|---|---|
| Hover card or popover visible | 2 s |
| Playing | 5 s, plus one extra fetch scheduled at the expected track end (`duration − progress + 300 ms`) |
| Paused (device still active) | 15 s |
| No active device (`204 No Content`) | 30 s |
| Screen locked, display asleep or system sleep | stopped; resume with an immediate fetch on wake or unlock |

Other rules:

- Fetch immediately after any control action and on every local Spotify
  notification.
- **429:** honour `Retry-After` and back off exponentially (max 60 s).
- **5xx or network errors:** back off exponentially (max 60 s) and keep the
  last state with a stale indicator after 60 s.
- **Progress is interpolated locally.** Calculate it from the last fetch's
  `progress_ms` plus elapsed time while `is_playing`.
- The progress bar animates only while the hover card or popover is visible,
  using a `TimelineView` or a 1 s tick. **The menu bar item never redraws on a
  timer.** It changes only when the track, play state or device changes.

### Identifying "this Mac"

The Web API doesn't flag the local client. The active device counts as this
Mac when **all** of these are true:

- Its `type` is `Computer`.
- The local Spotify app is running (`NSRunningApplication` for
  `com.spotify.client`).
- The most recent local `PlaybackStateChanged` notification's track ID and
  playing state match the API's.

Otherwise it is treated as a remote device, even if it is another Mac. This
is Claude's call: the device name can't be trusted, because people rename
Macs and Spotify devices.

### Controls (Web API)

- Play/pause: `PUT /me/player/play` and `PUT /me/player/pause`
- Next: `POST /me/player/next`
- Previous: `POST /me/player/previous`
- Volume: `PUT /me/player/volume?volume_percent=N`
  - Debounce slider drags (~150 ms) and send the final value on release.
- Devices list: `GET /me/player/devices`
  - Fetch when the popover opens, then every 10 s while it stays open.
- Transfer: `PUT /me/player` with body `{"device_ids":[id],"play":true}`

All controls update the UI **optimistically** and reconcile with the next
fetch. On failure, revert the change and show a brief inline error in the card
or popover. If no device is active, play/pause attempts `PUT /me/player/play`
on the last known device.

### Open Spotify

Use `NSWorkspace` to open the `com.spotify.client` bundle. If Spotify isn't
installed, open `https://open.spotify.com` in the default browser.

### Authentication

- **Authorization Code with PKCE.** No client secret is stored.
- The flow runs in `ASWebAuthenticationSession` with redirect URI
  `spotifybar://callback`. Mrinal registers this exact URI in the Spotify
  developer dashboard.
- Scopes: `user-read-playback-state`, `user-modify-playback-state`,
  `user-read-currently-playing`.
- The **Client ID** is entered in Settings on first run and stored in
  UserDefaults. A README section explains how to create the Spotify app.
- The **access token, refresh token and expiry** are stored in the
  **Keychain**.
- Refresh proactively 60 s before expiry and on any 401. Store the rotated
  refresh token when Spotify returns one.
- If refresh fails with `invalid_grant`, show the signed-out state.

### Artwork

- Spotify returns 640, 300 and 64 px images.
  - Menu bar: the **64 px** image, drawn at 18 pt.
  - Hover card art and popover: the **300 px** image.
  - Blurred card background: the **64 px** image, upscaled and blurred.
    That's cheap and looks the same.
- Cache in memory with `NSCache` keyed by URL.
- Also cache on disk in `~/Library/Caches/<bundle id>/art/`, capped at about
  50 MB with LRU eviction.
- Decode off the main thread.

### UI implementation

- **Status item:** `NSStatusItem` with `variableLength`. Its button hosts an
  `NSHostingView` with the SwiftUI bar view.
  - An `NSTrackingArea` on the button drives the hover state for the inline
    controls and the hover card's 350 ms delay.
  - The width change animates when the inline controls appear on hover.
- **Hover card:** a non-activating `NSPanel` (`.nonactivatingPanel`,
  `.statusBar` level, `canBecomeKey = false` so it never steals focus)
  positioned under the status item. Use the same tracking logic for the
  grace period.
- **Click popover:** a **non-activating `NSPanel`** that can become key
  (`.nonactivatingPanel` with `canBecomeKey = true`, the Spotlight-style
  pattern), anchored under the status item.
  - It receives keyboard input without activating the app, so the app
    Mrinal is working in keeps focus. Do **not** call `NSApp.activate`.
  - It closes on Esc, on a click outside (global mouse-down monitor) and
    when the item is clicked again.
  - *Claude's call: NSPopover was rejected because it requires activating
    the app to get key input.*
- **Accessibility:** VoiceOver labels on all controls, and a "Now playing:
  <title> by <artist> on <device>" label on the status item.
- **Reduce Motion:** disable the width animation and any card transitions.
- **Reduce Transparency:** use a solid material instead of glass.

### State and architecture

The structure is a guide. File and type names are the builder's choice.

- **`SpotifyAuth`:** PKCE, token store and refresh.
- **`SpotifyAPI`:** typed async endpoints and Codable models.
- **`PlaybackStore`:** an `@Observable` `@MainActor` single source of truth.
  It merges Web API results, local-notification triggers and optimistic
  updates.
- **`PollScheduler`:** the adaptive scheduler, aware of sleep and lock.
- **`ArtworkCache`**
- **`StatusItemController`**, **`HoverCardController`**, **`PopoverController`**
  (AppKit glue) and the SwiftUI views.

### Edge states

| Situation | Bar item | Hover card / popover |
|---|---|---|
| Not signed in or no Client ID | Music-note glyph | Card and popover show a "Sign in with Spotify" button, plus a link to Settings if there's no Client ID |
| Signed in, nothing active (204) | Music-note glyph, dimmed | "Nothing playing", the device list (from `/me/player/devices`) to start playback, and Open Spotify |
| Ad, podcast episode or local file | Show what the API returns. Podcast episodes use show art and name; ads show "Advertisement". Request `additional_types=episode`. | Same |
| Device without volume support | Normal | Volume slider disabled, with a "Volume controlled on device" hint |
| Network down or API errors for over 60 s | Last state, with the text dimmed | Small "Offline" note |

### Settings window

A small SwiftUI `Settings` scene containing:

- Spotify Client ID with Sign In / Sign Out.
- Launch at login, using `SMAppService.mainApp`.
- Show artist line (default on).
- Max title width (default 132 pt).

### Performance budgets

These must be verified before calling v1 done.

- Idle CPU (playing, no UI open): **< 0.5 % average** over 5 minutes in
  Activity Monitor.
- Memory: **< 40 MB** resident.
- Network: about 12–15 requests a minute while playing with no UI open.
  This is a soft target, not a hard ceiling. Event-driven fetches (a local
  notification, a control action or the track end) **replace** the next
  scheduled poll rather than adding to it, and repeat triggers within 1 s are
  coalesced into one fetch.
- Launch to first track shown: **< 1 s** when already signed in.
- Hover card appears within one frame of the 350 ms delay. Art comes from
  cache when the track hasn't changed.

### Testing

- Unit tests (XCTest or Swift Testing):
  - PKCE generation.
  - Token refresh logic.
  - `PlaybackStore` merge and optimistic-revert.
  - `PollScheduler` interval choice.
  - Decoding `/me/player` fixtures: track, episode, ad, 204 and a device
    without volume.
- Manual checks:
  - Play on phone, TV or speaker and on this Mac.
  - Switch devices.
  - Sleep and wake.
  - Network off.
  - Sign out.

### Distribution

Personal use only. The app is built locally and ad-hoc signed, then copied to
`/Applications`. There is no notarization, Sparkle or App Store in v1.

## Left to the builder

- The exact app name and icon.
- File and module layout.
- Exact animation curves.
- Glyph mapping for Spotify device types (`Computer`, `Smartphone`,
  `Speaker`, `TV`, `CastVideo`, `CastAudio`, `Automobile`, and so on).
