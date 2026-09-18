#!/bin/bash
set -euo pipefail
# RelayBar — Unified Self-Test Runner
# Replaces the individual *_Test.command scripts with one parameterized entry point.

ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/BuildLogs"
LOG="$ROOT/BuildLogs/self-test-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1
finish() { if [[ -t 0 ]]; then printf '\nPress Return to close. '; read -r _ || true; fi; }
trap finish EXIT

SUITE="${1:-help}"

usage() {
    cat <<EOF
RelayBar Self-Test Runner

Usage:  ./Run_Self_Test.command <suite>

Suites:
  button-families    Run the native Touch Bar button-families construction test
  context-stack      Run the Context Stack clipboard-collection test
  claim-ledger       Run the Claim Ledger review/refusal/receipt test (no command is executed)
  pinned-chats       Run the Pinned Chats sidebar-parsing test
  screenshot         Run the Screenshot Shelf filesystem test
  smoke              Run the quick native-component smoke test
  all                Run every suite above sequentially
  help               Show this message

Examples:
  ./Run_Self_Test.command button-families
  ./Run_Self_Test.command all
EOF
}

if [[ "$(uname -s)" != "Darwin" ]]; then echo 'Self-tests require macOS.'; exit 2; fi

APP="$ROOT/build/RelayBar.app"
BIN="$APP/Contents/MacOS/RelayBar"
if [[ ! -x "$BIN" ]]; then
    printf 'App not built. Building now...\n'
    bash "$ROOT/Scripts/build.sh"
fi
if [[ ! -x "$BIN" ]]; then echo "Build failed. Cannot run tests."; exit 1; fi

run_suite() {
    local name="$1" flag="$2"
    printf '\n═══ %s ═══\n' "$name"
    if "$BIN" "$flag"; then
        printf '✓ %s passed\n' "$name"
        return 0
    else
        printf '✗ %s FAILED\n' "$name"
        return 1
    fi
}

case "$SUITE" in
    button-families) run_suite "Button Families" "--button-families-self-test" ;;
    context-stack)   run_suite "Context Stack"   "--context-stack-self-test" ;;
    claim-ledger)    run_suite "Claim Ledger"    "--claim-ledger-self-test" ;;
    pinned-chats)    run_suite "Pinned Chats"    "--pinned-chats-self-test" ;;
    screenshot)      run_suite "Screenshot Shelf" "--screenshot-self-test" ;;
    smoke)           run_suite "Smoke Test"      "--smoke-test" ;;
    all)
        PASSED=0 FAILED=0
        for suite_args in \
            "Button Families:--button-families-self-test" \
            "Context Stack:--context-stack-self-test" \
            "Claim Ledger:--claim-ledger-self-test" \
            "Pinned Chats:--pinned-chats-self-test" \
            "Screenshot Shelf:--screenshot-self-test" \
            "Smoke Test:--smoke-test"; do
            name="${suite_args%%:*}"
            flag="${suite_args#*:}"
            if run_suite "$name" "$flag"; then
                PASSED=$((PASSED + 1))
            else
                FAILED=$((FAILED + 1))
            fi
        done
        printf '\n═══ Results: %d passed, %d failed ═══\n' "$PASSED" "$FAILED"
        [[ "$FAILED" -eq 0 ]] || exit 1
        ;;
    help|--help|-h) usage; exit 0 ;;
    *)
        printf 'Unknown suite: %s\n\n' "$SUITE"
        usage
        exit 2
        ;;
esac

printf '\nLog: %s\nNo physical Touch Bar rendering or assistant-routing test was performed.\n' "$LOG"
