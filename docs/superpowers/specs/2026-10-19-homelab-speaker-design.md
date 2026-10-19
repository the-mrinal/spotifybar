# Homelab speaker awareness: design

## Why

Most listening ends up on one speaker, the Xiaomi Sound Outdoor, whatever device starts it. The homelab
(`~/homelab/apps/speaker` on the box) bridges two receivers to it over Bluetooth:

- the AirPlay 2 receiver "Xiaomi Soundbar AirPlay 2" (shairport-sync), used by the iPhone and the Mac, and
- the Spotify Connect device spotifyd (its name is in the status as `spotify.device_name`).

Spotify's Web API only knows the *sender*: it says "iPhone" while the sound is coming out of the Xiaomi, and it
often refuses to set an iPhone's volume. The homelab's `speaker.py` knows the real path and owns the speaker's volume,
battery, EQ and sleep timer through a small JSON API (`GET /api/status`, `POST /api/speaker/volume {value}`,
`/api/eq {preset}`, `/api/sleep {minutes}`, `/api/speaker/connect`, `GET /api/airplay/cover`). There's no auth on it.

## Goals

1. **One volume = how loud the Xiaomi is.** When the sound reaches the Xiaomi, the slider and ↑/↓ control it:

   | Source | Slider sets | Why |
   |---|---|---|
   | Mac → AirPlay → Xiaomi | the Mac's output volume (CoreAudio) | shairport-sync maps the sender's AirPlay volume onto the speaker (`ignore_volume_control`), and the Mac's volume keys stay in step |
   | iPhone (or other) → AirPlay → Xiaomi | the speaker, via `POST /api/speaker/volume` | the phone's slider won't follow (AirPlay 2 has no way back) |
   | the homelab's Spotify Connect device | the speaker, via the homelab | |
   | anything else | Spotify's device volume, as before | |

   A small caption under the slider names the target ("Xiaomi Sound Outdoor · via Mac AirPlay").
   If Spotify's own volume is below 100 % while it feeds the Xiaomi (and Spotify allows changing it), a quiet line offers "Set to 100%".
2. **Battery, subtle.** A small battery glyph and percentage in the hover card and the remote. The menu bar shows nothing
   unless it's low (< 20 % and not charging), and then only a small dot on the device glyph.
3. **The real path.** The device chip and the remote header say where the sound comes out: "iPhone → Xiaomi Sound Outdoor".
   The menu bar's device glyph becomes a speaker.
4. **Non-Spotify AirPlay.** When nothing is playing in Spotify but the phone is AirPlaying another app, show the AirPlay
   title, artist and cover art (`/api/airplay/cover`). Transport and progress are hidden (no remote control path over AirPlay 2).
5. **EQ presets** (from `eq.presets`) as one compact row in the remote.
6. **Sleep timer** menu in the remote (`sleep.choices`), showing the remaining time while it's set.
7. **Play on the Xiaomi directly**: when a phone is AirPlaying Spotify to the speaker and the homelab's Spotify device is listed,
   a one-tap button transfers Spotify to it.
8. **Connection health**: when the speaker API reports the Bluetooth link down, a quiet "Speaker disconnected · Reconnect" line.

## Non-goals

- Controlling the iPhone's AirPlay session (play/pause/skip for non-Spotify apps). AirPlay 2 gives the receiver no remote control.
- Changing the homelab. Everything here uses the existing API.
- Any setup UI beyond a URL field.

## Constraints

- Off by default: a "Homelab speaker URL" setting (empty = off). If the URL can't be reached, every speaker feature
  hides and the app behaves exactly as before.
- Plain HTTP on the LAN / tailnet: the app needs an ATS exception and a local-network usage string.
- Polling the speaker: every 3 s while a card or the remote is open, 10 s otherwise, stopped while the Mac is asleep or locked,
  backing off to 30 s while unreachable.
- Route resolution and decoding live in `SpotifyBarCore` and are unit-tested; CoreAudio and HTTP stay behind small seams.

## Builder's calls (mine)

- "Sound reaches the Xiaomi" = speaker connected **and** either (a) the Spotify device's name equals `spotify.device_name`,
  or (b) `airplay.session` is true. The Mac is the AirPlay sender when its default output device's transport type is AirPlay
  (or `airplay.client_name` equals the Mac's computer name).
- The sender's display name drops a leading "Name’s " ("Mrinal’s iPhone" → "iPhone"); the Mac is "This Mac".
