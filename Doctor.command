#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/BuildLogs"
LOG="$ROOT/BuildLogs/doctor-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1
finish() { if [[ -t 0 ]]; then printf '\nPress Return to close. '; read -r _ || true; fi; }
trap finish EXIT
printf 'RelayBar diagnostics — no clipboard, selection, project text, or messages are read.\n\n'
uname -sm
if [[ "$(uname -s)" != "Darwin" ]]; then echo 'Run Doctor.command on macOS.'; exit 2; fi
source "$ROOT/Scripts/toolchain.sh"
rb_prepare_toolchain "$ROOT"
rb_preflight "$(uname -m)"
APP="$HOME/Applications/RelayBar.app"
if [[ ! -x "$APP/Contents/MacOS/RelayBar" ]]; then APP="$ROOT/build/RelayBar.app"; fi
if [[ ! -x "$APP/Contents/MacOS/RelayBar" ]]; then
    printf 'RelayBar has not been built. Building now...\n'
    bash "$ROOT/Scripts/build.sh"
    if [[ ! -x "$APP/Contents/MacOS/RelayBar" ]]; then echo 'Build failed. Cannot run diagnostics.'; exit 2; fi
fi
/usr/bin/codesign --verify --strict "$APP"
"$APP/Contents/MacOS/RelayBar" --diagnostics
"$APP/Contents/MacOS/RelayBar" --smoke-test
printf '\nLog: %s\nNo physical Touch Bar rendering or assistant-routing test was performed by this script.\n' "$LOG"
