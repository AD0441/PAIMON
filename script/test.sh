#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/lai-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/lai-swift-cache"
# Build outside File Provider/iCloud directories to avoid FinderInfo signing errors.
swift test --disable-sandbox --scratch-path "${TMPDIR:-/tmp}/LocalAudioIntelligence-tests" -j 2 "$@"
