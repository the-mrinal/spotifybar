# SpotifyBar

A tiny native macOS menu bar app that shows what Spotify is playing, **on any device**: this Mac, your phone, a smart speaker or the TV. It also lets you control it without leaving what you're working on.

- **Menu bar:** 18 pt album art, with the title stacked over the artist and an icon for the device that's playing. Hover to get previous / play-pause / next right in the bar.
- **Hover card:** large album art on art-tinted Liquid Glass, with progress, controls and volume. It appears without a click and never steals focus.
- **Click:** a device remote with "Playing on …", device volume, "Switch to" another device, and Open Spotify. Keyboard shortcuts while it's open:

  | Key | Action |
  |---|---|
  | Space | Play / pause |
  | ← → | Previous / next track |
  | ↑ ↓ | Volume |
  | Esc | Close |

It's written in Swift 6 with SwiftUI and AppKit, and has no third-party dependencies. When signed out it uses about 0% CPU and about 23 MB of memory.

## Requirements

- macOS 26 or later.
- **Spotify Premium.** Spotify only allows playback control through its Web API for Premium accounts.
- Your own Spotify developer app (free, about 2 minutes to set up). In Development Mode, an app works for its owner plus up to 4 other users.

## Set up your Spotify app

1. Open <https://developer.spotify.com/dashboard> and **Create app**.
2. Under **Redirect URIs**, add exactly `spotifybar://callback`.
3. Under **Which API/SDKs are you planning to use?**, tick **Web API**, then save.
4. Copy the app's **Client ID**.
5. Launch SpotifyBar. Settings opens on first run. Paste the Client ID and click **Sign in with Spotify**.

## Build

```sh
brew install xcodegen
./scripts/test.sh                  # unit tests
./scripts/build-release.sh         # → build/Build/Products/Release/SpotifyBar.app and build/SpotifyBar.zip
cp -R build/Build/Products/Release/SpotifyBar.app /Applications/
```

The app is ad-hoc signed and not notarized. If Gatekeeper complains about a downloaded build, right-click the app and choose **Open**, or run `xattr -dr com.apple.quarantine /Applications/SpotifyBar.app`.

## How it works

- **Spotify Web API:** `GET /me/player` is the source of truth, which is how playback on other devices is visible.
- **Polling is adaptive:**

  | State | Interval |
  |---|---|
  | Card or remote open | 2 s |
  | Playing | 5 s, plus one fetch at the end of the track |
  | Paused | 15 s |
  | Nothing playing | 30 s |
  | Mac asleep or locked | stopped |

  Rate limits (`429 Retry-After`) and errors back off for up to 60 s.
- **Local trigger:** when the Spotify app on this Mac changes track or state, its `com.spotify.client.PlaybackStateChanged` broadcast triggers an immediate fetch. The app doesn't use AppleScript, so you get no Automation permission prompt.
- **Optimistic controls:** controls update the UI immediately and revert if Spotify rejects the change.
- **No timer redraws:** the menu bar item only redraws when the track, play state or device changes.

## Privacy

- Tokens (PKCE, with no client secret) are stored in your login Keychain.
- The app talks only to `accounts.spotify.com`, `api.spotify.com` and Spotify's image CDN.
- Album art is cached in `~/Library/Caches/dev.mrinal.SpotifyBar/art` (capped at 50 MB).

## Project layout

```
Sources/SpotifyBarCore/   Web API client, PKCE auth, playback store, poll scheduler, artwork cache (unit-tested)
Sources/SpotifyBar/       menu bar item, hover card, remote panel, settings (AppKit + SwiftUI)
Tests/                    Swift Testing suites + API fixtures
docs/                     design spec, implementation plan, Open Design mockups
```

The design came from [Open Design](docs/design/). The chosen combination was `BAR=D HOVER=B CLICK=D`.

## Credits

[SpotMenu](https://github.com/kmikiy/SpotMenu) (MIT) was used as a reference for the PKCE flow. No code was copied.

## License

MIT
