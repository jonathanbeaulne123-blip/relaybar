#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/BuildLogs"
LOG="$ROOT/BuildLogs/core-tests-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1
finish() { if [[ -t 0 ]]; then printf '\nPress Return to close. '; read -r _ || true; fi; }
trap finish EXIT
printf 'Testing the local engine. No app permissions, API keys, or network dependencies.\n'
if [[ "$(uname -s)" == "Darwin" ]]; then
  source "$ROOT/Scripts/toolchain.sh"
  rb_prepare_toolchain "$ROOT"
  rb_preflight "$(uname -m)"
  # Forward the same view to both Package.swift and the test sources. Merely
  # forwarding -Xswiftc misses the manifest compiler, which imports Foundation.
  HELP="$("$RB_SWIFT" test --help-hidden)"
  if [[ "$HELP" == *"-Xbuild-tools-swiftc"* ]]; then
    MANIFEST_FLAG=-Xbuild-tools-swiftc
  elif [[ "$HELP" == *"-Xmanifest"* ]]; then
    MANIFEST_FLAG=-Xmanifest
  else
    echo 'This SwiftPM does not expose manifest compiler flags. Keep the toolchain log.'
    exit 2
  fi
  EXTRA=()
  for flag in "${RB_SWIFT_FLAGS[@]}"; do
    EXTRA+=(-Xswiftc "$flag" "$MANIFEST_FLAG" "$flag")
  done
  export SWIFT_EXEC="$RB_SWIFTC" SWIFT_EXEC_MANIFEST="$RB_SWIFTC" CC="$RB_CLANG"
  "$RB_SWIFT" test --package-path "$ROOT" --scratch-path "$RB_RUN/swiftpm" \
    --sdk "$RB_SDK" "${EXTRA[@]}"
else
  swift test --package-path "$ROOT" --scratch-path "$ROOT/.build-tests"
fi
printf '\nSaved test output: %s\n' "$LOG"
