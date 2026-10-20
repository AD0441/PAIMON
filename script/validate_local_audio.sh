#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT_DIR/script/build_and_run.sh" --build-only
APP_BUNDLE="${TMPDIR:-/tmp}/LocalAudioIntelligence-DerivedData/Build/Products/Debug/PAIMON.app"
REPORT="${1:-${TMPDIR:-/tmp}/paimon-capture-validation.json}"
VALIDATION_DIR=$(mktemp -d "${TMPDIR:-/tmp}/paimon-validation.XXXXXX")
# A GUI app must not request Desktop-folder permission just to run its fixture.
# The shell has the user's project access; give the app only a temporary copy.
/bin/cp "$ROOT_DIR/Tests/Fixtures/spanish-synthetic.aiff" "$VALIDATION_DIR/sample.aiff"
printf '%s\n' 'This plays a short synthetic voice sample and captures only this app output. Allow macOS system audio permission if prompted.'
/usr/bin/open -n "$APP_BUNDLE" --args --validate-audio "$VALIDATION_DIR/sample.aiff" "$VALIDATION_DIR/result.json"
for ((ATTEMPT=0; ATTEMPT<90; ATTEMPT++)); do
  if [[ -s "$VALIDATION_DIR/result.json" ]]; then
    /bin/cp "$VALIDATION_DIR/result.json" "$REPORT"
    if [[ -f "$VALIDATION_DIR/result.session.json" ]]; then /bin/cp "$VALIDATION_DIR/result.session.json" "${REPORT%.json}.session.json"; fi
    printf 'Result: %s\n' "$REPORT"
    python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("passed") else 1)' "$REPORT"
    exit
  fi
  sleep 1
done
printf 'Validation did not finish. Check macOS permissions and the app state. Diagnostic directory: %s\n' "$VALIDATION_DIR" >&2
exit 1
