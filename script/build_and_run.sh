#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
CONFIGURATION="Debug"
if [[ "$MODE" == "--install" ]]; then CONFIGURATION="Release"; fi
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="PAIMON"
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/lai-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/lai-swift-cache"
DERIVED="${TMPDIR:-/tmp}/LocalAudioIntelligence-DerivedData"
APP_BUNDLE="$DERIVED/Build/Products/$CONFIGURATION/$APP_NAME.app"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x LocalAudioIntelligence >/dev/null 2>&1 || true
cd "$ROOT_DIR"
xcodebuild -project LocalAudioIntelligence.xcodeproj -scheme LocalAudioIntelligence -configuration "$CONFIGURATION" -derivedDataPath "$DERIVED" -destination 'platform=macOS' -jobs 2 build
case "$MODE" in
  --build-only) printf '%s\n' "$APP_BUNDLE" ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 2; pgrep -x "$APP_NAME" >/dev/null ;;
  --install)
    PROJECT_BUNDLE="$ROOT_DIR/PAIMON.app"
    INSTALLED_BUNDLE="/Applications/PAIMON.app"
    for DESTINATION in "$PROJECT_BUNDLE" "$INSTALLED_BUNDLE"; do
    if [[ -e "$DESTINATION" ]]; then
      EXISTING_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist")
      if [[ "$EXISTING_ID" != "local.audio.intelligence" ]]; then
        printf 'La aplicación de destino no corresponde a este proyecto: %s\n' "$DESTINATION" >&2
        exit 1
      fi
    fi
    done
    /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
    VERSIONS_DIR="$ROOT_DIR/Versiones"
    PORTABLE_ARCHIVE="$VERSIONS_DIR/PAIMON-actual.zip"
    PREVIOUS_ARCHIVE="$VERSIONS_DIR/PAIMON-anterior.zip"
    PACKAGE_CHECK=$(mktemp -d "${TMPDIR:-/tmp}/paimon-package-check.XXXXXX")
    INSTALL_VALIDATED=false
    cleanup_package() {
      # Restore the original bundle if replacement or signature verification fails.
      if [[ "$INSTALL_VALIDATED" == false && -e "$PACKAGE_CHECK/replaced.app" ]]; then
        /bin/rm -rf -- "$INSTALLED_BUNDLE"
        /bin/mv "$PACKAGE_CHECK/replaced.app" "$INSTALLED_BUNDLE" || return
      fi
      /bin/rm -rf -- "$PACKAGE_CHECK"
    }
    trap cleanup_package EXIT
    package_verified() {
      /usr/bin/ditto --norsrc -c -k --keepParent "$1" "$2"
      /usr/bin/ditto -x -k "$2" "$3"
      /usr/bin/codesign --verify --deep --strict "$3/PAIMON.app"
    }
    signature_id() {
      /usr/bin/codesign -d --verbose=4 "$1" 2>&1 | /usr/bin/awk '/^CDHash=/{print $0}'
    }
    version_id() {
      /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist"
      /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$1/Contents/Info.plist"
    }
    trash_bundle() {
      /usr/bin/xcrun swift -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" -e '
        import Foundation
        try FileManager.default.trashItem(at: URL(fileURLWithPath: CommandLine.arguments[1]), resultingItemURL: nil)
      ' "$1"
    }
    package_verified "$APP_BUNDLE" "$PACKAGE_CHECK/actual.zip" "$PACKAGE_CHECK/current"
    # Recompiling the same declared version/build only replaces the current ZIP.
    # Keep the previous released build rather than an intermediate UI revision.
    if [[ -e "$INSTALLED_BUNDLE" ]]; then
      /usr/bin/codesign --verify --deep --strict "$INSTALLED_BUNDLE"
      if [[ "$(version_id "$INSTALLED_BUNDLE")" != "$(version_id "$APP_BUNDLE")" ]] && [[ "$(signature_id "$INSTALLED_BUNDLE")" != "$(signature_id "$APP_BUNDLE")" ]]; then
        package_verified "$INSTALLED_BUNDLE" "$PACKAGE_CHECK/anterior.zip" "$PACKAGE_CHECK/previous"
      fi
    fi
    # Replace instead of merging bundles: old resources can invalidate a new signature.
    if [[ -e "$INSTALLED_BUNDLE" ]]; then
      /bin/mv "$INSTALLED_BUNDLE" "$PACKAGE_CHECK/replaced.app"
    fi
    /usr/bin/ditto --norsrc "$PACKAGE_CHECK/current/PAIMON.app" "$INSTALLED_BUNDLE"
    /usr/bin/codesign --verify --deep --strict "$INSTALLED_BUNDLE"
    INSTALL_VALIDATED=true
    /bin/mkdir -p "$VERSIONS_DIR"
    if [[ -e "$PACKAGE_CHECK/anterior.zip" ]]; then
      /bin/mv -f "$PACKAGE_CHECK/anterior.zip" "$PREVIOUS_ARCHIVE"
    fi
    /bin/mv -f "$PACKAGE_CHECK/actual.zip" "$PORTABLE_ARCHIVE"
    # A link avoids File Provider modifying the signed bundle in this folder.
    if [[ -L "$PROJECT_BUNDLE" ]]; then /bin/rm "$PROJECT_BUNDLE"
    elif [[ -e "$PROJECT_BUNDLE" ]]; then trash_bundle "$PROJECT_BUNDLE"; fi
    /bin/ln -s "$INSTALLED_BUNDLE" "$PROJECT_BUNDLE"
    /usr/bin/codesign --verify --deep --strict "$PROJECT_BUNDLE"
    for LEGACY in "$ROOT_DIR/Local Audio Intelligence.app" "/Applications/Local Audio Intelligence.app"; do
      if [[ -e "$LEGACY" ]] && [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LEGACY/Contents/Info.plist")" == "local.audio.intelligence" ]]; then
        trash_bundle "$LEGACY"
      fi
    done
    /usr/bin/open -n "$INSTALLED_BUNDLE"
    printf 'Aplicación junto al proyecto: %s\n' "$PROJECT_BUNDLE"
    printf 'Aplicación instalada: %s\n' "$INSTALLED_BUNDLE"
    printf 'Copia portátil verificada: %s\n' "$PORTABLE_ARCHIVE"
    ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "PAIMON"' ;;
  --telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "local.audio.intelligence"' ;;
  *) printf 'usage: %s [run|--build-only|--verify|--install|--debug|--logs|--telemetry]\n' "$0" >&2; exit 2 ;;
esac
