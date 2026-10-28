#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/Resources/Brand/PAIMON-icon.png"
STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/paimon-icon.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT
ICONSET="$STAGING_DIR/Paimon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
    /usr/bin/sips -z "$SIZE" "$SIZE" "$SOURCE" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    RETINA_SIZE=$((SIZE * 2))
    /usr/bin/sips -z "$RETINA_SIZE" "$RETINA_SIZE" "$SOURCE" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$ROOT_DIR/Resources/Paimon.icns"
printf 'Icono generado: %s\n' "$ROOT_DIR/Resources/Paimon.icns"
