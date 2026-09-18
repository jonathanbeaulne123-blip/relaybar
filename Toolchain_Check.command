#!/bin/bash
# No app installation. Writes only local compiler probes/caches/logs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
umask 077
mkdir -p "$ROOT/BuildLogs"
LOG="$ROOT/BuildLogs/toolchain-$(date +%Y%m%d-%H%M%S)-$$.log"
exec > >(tee "$LOG") 2>&1
finish() {
  result=$?
  printf '\nToolchain check exit: %s\nLog: %s\n' "$result" "$LOG"
  if [[ -t 0 ]]; then printf '\nPress Return to close. '; read -r _ || true; fi
}
trap finish EXIT
source "$ROOT/Scripts/toolchain.sh"
rb_prepare_toolchain "$ROOT"
rb_preflight "$(uname -m)"
echo 'Compiler probe passed. This does not establish that the full app builds or that a Touch Bar renders.'
echo 'Run Install.command in this folder to build and install the application.'
