#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi
FIXTURE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/paimon-fixture-player.XXXXXX")
FIXTURE_APP="$FIXTURE_DIR/PAIMON Audio Fixture.app"
mkdir -p "$FIXTURE_APP/Contents/MacOS" "$FIXTURE_APP/Contents/Resources"
cp "$ROOT_DIR/Tests/Fixtures/spanish-synthetic.aiff" "$FIXTURE_APP/Contents/Resources/sample.aiff"
cat > "$FIXTURE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.audio.intelligence.fixtureplayer</string>
<key>CFBundleName</key><string>PAIMON Audio Fixture</string>
<key>CFBundleExecutable</key><string>FixturePlayer</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
</dict></plist>
PLIST
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos26.0 "$ROOT_DIR/script/AudioFixturePlayer.swift" -o "$FIXTURE_APP/Contents/MacOS/FixturePlayer" -framework AppKit -framework AVFoundation
codesign --force --sign - "$FIXTURE_APP"
open -n "$FIXTURE_APP"
printf 'Reproductor de prueba: %s\n' "$FIXTURE_APP"
printf '%s\n' 'En PAIMON, elige la fuente PAIMON Audio Fixture, pulsa Iniciar y luego Reproducir muestra en esta ventana. Al terminar, Detener en PAIMON. No recompiles PAIMON después de autorizar su permiso.'
