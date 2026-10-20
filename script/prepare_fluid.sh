#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi
VENDOR="Integrations/FluidWorker/Vendor/FluidAudio"
EXPECTED_COMMIT="a6b826ce9a09028fc685a4b32a8927ec920c3188"
# Explicit invocation authorizes source download; no model is downloaded.
if [[ ! -d "$VENDOR/.git" ]]; then
  git clone --depth 1 --branch v0.17.3 https://github.com/FluidInference/FluidAudio.git "$VENDOR"
fi
ACTUAL_COMMIT="$(git -C "$VENDOR" rev-parse HEAD)"
if [[ "$ACTUAL_COMMIT" != "$EXPECTED_COMMIT" ]]; then printf '%s\n' 'Unexpected FluidAudio commit; refusing to build.' >&2; exit 1; fi
# Keep all upstream implementation and LICENSE files intact. Only narrow the
# build graph to avoid downloading/linking the unrelated NeMo TTS normalizer.
cp Integrations/FluidWorker/FluidAudio-Package.swift "$VENDOR/Package.swift"
cp Integrations/FluidWorker/FluidAudio-Package.swift "$VENDOR/Package@swift-6.2.swift"
BUILD_DIR="${TMPDIR:-/tmp}/LAIFluidWorker-build"
swift build --package-path Integrations/FluidWorker --scratch-path "$BUILD_DIR" -c release -j 2
printf 'Worker: %s\n' "$(swift build --package-path Integrations/FluidWorker --scratch-path "$BUILD_DIR" -c release --show-bin-path)/FluidWorker"
printf '%s\n' 'No models downloaded. Prepare Parakeet Redux separately; see docs/DEPENDENCIES.md.'
