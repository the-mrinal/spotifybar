#!/bin/sh
# Builds a Release SpotifyBar.app (ad-hoc signed) and zips it into build/SpotifyBar.zip.
set -eu
cd "$(dirname "$0")/.."
xcodegen generate -q
xcodebuild -scheme SpotifyBar -configuration Release -destination 'platform=macOS' -derivedDataPath build build >build/release.log 2>&1 \
  || { tail -20 build/release.log; exit 1; }
APP=build/Build/Products/Release/SpotifyBar.app
rm -f build/SpotifyBar.zip
ditto -c -k --keepParent "$APP" build/SpotifyBar.zip
echo "$APP"
echo build/SpotifyBar.zip
