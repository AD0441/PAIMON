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
    /usr/bin/ditto --norsrc "$APP_BUNDLE" "$INSTALLED_BUNDLE"
    /usr/bin/codesign --verify --deep --strict "$INSTALLED_BUNDLE"
    APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALLED_BUNDLE/Contents/Info.plist")
    PORTABLE_ARCHIVE="$ROOT_DIR/PAIMON-$APP_VERSION.zip"
    /usr/bin/ditto --norsrc -c -k --keepParent "$INSTALLED_BUNDLE" "$PORTABLE_ARCHIVE"
    PACKAGE_CHECK=$(mktemp -d "${TMPDIR:-/tmp}/paimon-package-check.XXXXXX")
    /usr/bin/ditto -x -k "$PORTABLE_ARCHIVE" "$PACKAGE_CHECK"
    /usr/bin/codesign --verify --deep --strict "$PACKAGE_CHECK/PAIMON.app"
    MANAGED_PROJECT=false
    if [[ -L "$PROJECT_BUNDLE" ]] || /usr/bin/xattr -p 'com.apple.fileprovider.fpfs#P' "$PROJECT_BUNDLE" >/dev/null 2>&1; then MANAGED_PROJECT=true; fi
    if [[ "$MANAGED_PROJECT" == false ]]; then
      /usr/bin/ditto --norsrc "$APP_BUNDLE" "$PROJECT_BUNDLE"
      /usr/bin/xattr -dr com.apple.ResourceFork "$PROJECT_BUNDLE" 2>/dev/null || true
      /usr/bin/xattr -dr com.apple.FinderInfo "$PROJECT_BUNDLE" 2>/dev/null || true
      if ! /usr/bin/codesign --verify --deep --strict "$PROJECT_BUNDLE"; then MANAGED_PROJECT=true; fi
    fi
    # File Provider can reattach FinderInfo after a successful verification.
    # Keep a portable zip plus a working app link instead of a damaged bundle.
    if [[ "$MANAGED_PROJECT" == true ]]; then
      if [[ -L "$PROJECT_BUNDLE" ]]; then /bin/rm "$PROJECT_BUNDLE"
      elif [[ -e "$PROJECT_BUNDLE" ]]; then
        PROJECT_BACKUP=$(mktemp -d "${TMPDIR:-/tmp}/paimon-project-bundle.XXXXXX")
        /bin/mv "$PROJECT_BUNDLE" "$PROJECT_BACKUP/PAIMON.app"
        printf 'Copia anterior del proyecto conservada en: %s\n' "$PROJECT_BACKUP/PAIMON.app"
      fi
      /bin/ln -s "$INSTALLED_BUNDLE" "$PROJECT_BUNDLE"
      printf 'File Provider: el proyecto usa un enlace a la app firmada y una copia ZIP portátil.\n'
    fi
    /usr/bin/codesign --verify --deep --strict "$PROJECT_BUNDLE"
    # Retire only this app's previous name, preserving the bundles for recovery.
    PREVIOUS_DIR=""
    for LEGACY in "$ROOT_DIR/Local Audio Intelligence.app" "/Applications/Local Audio Intelligence.app"; do
      if [[ -e "$LEGACY" ]] && [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$LEGACY/Contents/Info.plist")" == "local.audio.intelligence" ]]; then
        if [[ -z "$PREVIOUS_DIR" ]]; then PREVIOUS_DIR=$(mktemp -d "${TMPDIR:-/tmp}/paimon-previous.XXXXXX"); fi
        if [[ "$LEGACY" == /Applications/* ]]; then PREVIOUS_NAME="Applications.app"; else PREVIOUS_NAME="Project.app"; fi
        /bin/mv "$LEGACY" "$PREVIOUS_DIR/$PREVIOUS_NAME"
      fi
    done
    if [[ -n "$PREVIOUS_DIR" ]]; then printf 'Versiones anteriores conservadas en: %s\n' "$PREVIOUS_DIR"; fi
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
