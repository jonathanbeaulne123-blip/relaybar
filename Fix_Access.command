#!/bin/bash
# No-build recovery for the exact RelayBar 0.9.1 build 17 installation.
# Does not grant permission, edit/sign the app, run its executable from Terminal,
# or reset any permission other than Accessibility for local.relaybar.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=C
umask 077
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
if [[ -d "$HOME/Downloads/RelayBar.app" ]]; then
    APP="$HOME/Downloads/RelayBar.app"
else
    APP="$HOME/Applications/RelayBar.app"
fi
PLIST="$APP/Contents/Info.plist"
BIN="$APP/Contents/MacOS/RelayBar"
REPORT=""
RESET_DONE=0

say() { printf '%s\n' "$*"; }
record() { if [[ -n "$REPORT" ]]; then printf '%s\n' "$*" >> "$REPORT"; fi; }
stop() { say "STOP: $*" >&2; record "Stopped: $*"; exit 2; }
finish() {
    result=$?
    trap - EXIT
    if [[ -n "$REPORT" ]]; then
        record "Helper exit status: $result"
        say ""
        say "Local recovery report: $REPORT"
    fi
    if [[ $RESET_DONE -eq 1 && $result -ne 0 ]]; then
        say 'The app-specific reset already ran. Do not rebuild or repeat the reset blindly.'
    fi
    if [[ -t 0 ]]; then printf '\nPress Return to close this window. '; read -r _ || true; fi
    exit "$result"
}
trap finish EXIT

say "RELAYBAR — PERMISSION RECOVERY (NO REBUILD)"
say "Targeting installed app: ~/Applications/RelayBar.app"
say 'This checks ~/Applications/RelayBar.app, then offers one app-specific reset.'
say 'It never grants permission or claims that a launch proves permission is granted.'
say ''
[[ $# -eq 0 ]] || stop 'Run without arguments.'
[[ "$(/usr/bin/uname -s)" == 'Darwin' ]] || stop 'This recovery runs on macOS only. Nothing was reset.'
[[ "$(/usr/bin/id -u)" != '0' ]] || stop 'Run as your normal Mac user, not with sudo or as root.'
case "$HOME" in /*) ;; *) stop 'HOME must be an absolute user home directory.' ;; esac
[[ "$HOME" != '/' ]] || stop 'Refusing the root directory as a user home.'
for path in "$HOME/Applications" "$APP" "$APP/Contents" "$APP/Contents/MacOS" "$PLIST" "$BIN"; do
    [[ ! -L "$path" ]] || stop 'The app path contains a symbolic link. Nothing was reset.'
done
[[ -f "$PLIST" && -f "$BIN" && -x "$BIN" ]] || stop 'The installed app is missing or incomplete at ~/Applications/RelayBar.app. Nothing was reset.'

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null; }
IDENTIFIER="$(plist CFBundleIdentifier)" || stop 'Cannot read the installed bundle identifier.'
VERSION="$(plist CFBundleShortVersionString)" || stop 'Cannot read the installed version.'
BUILD="$(plist CFBundleVersion)" || stop 'Cannot read the installed build number.'
EXECUTABLE="$(plist CFBundleExecutable)" || stop 'Cannot read the installed executable name.'
[[ "$IDENTIFIER" == 'local.relaybar' && "$EXECUTABLE" == 'RelayBar' ]] || stop 'This is not the expected RelayBar bundle. Nothing was reset.'

verify_signature() {
    /usr/bin/codesign --verify --strict --all-architectures "$APP" || stop 'Installed code-signature verification failed. Do not re-sign or rebuild it as a troubleshooting shortcut.'
}
file_hash() { /usr/bin/shasum -a 256 < "$1" | /usr/bin/awk '{ print $1 }'; }
verify_signature
BIN_HASH="$(file_hash "$BIN")"
PLIST_HASH="$(file_hash "$PLIST")"
SIGNING="$(/usr/bin/codesign -d --verbose=4 "$APP" 2>&1)" || stop 'Cannot read the installed signature details.'
REQUIREMENT="$(/usr/bin/codesign -d -r- "$APP" 2>&1)" || stop 'Cannot read the installed signing requirement.'

REPORT_DIR="$(/usr/bin/mktemp -d "$ROOT/RecoveryReport.XXXXXX")" || stop 'Cannot create a private report folder beside this helper.'
REPORT="$REPORT_DIR/Report.txt"
{
    printf 'RelayBar permission recovery — local observations only\n'
    printf 'Target: ~/Applications/RelayBar.app\n'
    printf 'Bundle: %s\nVersion: %s\nBuild: %s\n' "$IDENTIFIER" "$VERSION" "$BUILD"
    printf 'Installed signature verification: passed\n'
    printf 'Executable SHA-256 before: %s\nInfo.plist SHA-256 before: %s\n' "$BIN_HASH" "$PLIST_HASH"
    printf '%s\n' "$SIGNING" | /usr/bin/awk '/^(Identifier=|Signature=|CDHash=|CodeDirectory |TeamIdentifier=)/ { print }'
    printf '%s\n' "$REQUIREMENT" | /usr/bin/awk '/^(# )?designated =>/ { print }'
    printf 'This helper does not inspect the TCC database or test another process\047s trust.\n'
    printf 'The running GUI app\047s Native connection report is the permission check.\n'
    printf 'No browser, cell, clipboard, screenshot or project contents were read.\n'
} > "$REPORT"

# A name check is deliberately conservative: do not terminate any process or
# decide that a different copy is harmless. All copies must be quit by the user.
require_closed() {
    local name="$1" result=0
    if /usr/bin/pgrep -x "$name" >/dev/null 2>&1; then
        stop "Quit $name normally, then run this helper again. No process was terminated."
    else
        result=$?
        [[ $result -eq 1 ]] || stop "Could not check whether $name is running."
    fi
}
require_closed 'RelayBar'
require_closed 'System Settings'
record 'No RelayBar or System Settings process was found before consent.'
say "Verified: RelayBar $VERSION, build $BUILD, at ~/Applications/RelayBar.app."
say 'Signature validation passed. This is not Apple notarization or a trust grant.'
say ''
say 'Save any drafts and quit RelayBar before continuing. The helper never force-quits it.'
say 'With your confirmation, the ONLY permission operation will be:'
say '    /usr/bin/tccutil reset Accessibility local.relaybar'
say "This clears RelayBar's Accessibility approval. Other permissions and apps are unchanged."
say 'It does not delete screenshots/projects, edit the app, create a certificate, or disable security.'
printf '\nType RESET to proceed, or press Return to cancel: '
read -r answer || answer=''
[[ "$answer" == 'RESET' ]] || { record 'Cancelled before the permission reset.'; say 'Cancelled. No permissions were reset.'; exit 0; }

# Re-check after the consent pause to avoid resetting while another copy starts
# or an installer replaces the bundle. There is exactly one tccutil call below.
require_closed 'RelayBar'
require_closed 'System Settings'
verify_signature
[[ "$(file_hash "$BIN")" == "$BIN_HASH" && "$(file_hash "$PLIST")" == "$PLIST_HASH" ]] || stop 'The app changed while this helper was open. Nothing was reset.'
if RESET_OUTPUT="$(/usr/bin/tccutil reset Accessibility local.relaybar 2>&1)"; then
    RESET_DONE=1
    record 'tccutil app-specific reset: succeeded (one invocation).'
else
    result=$?
    record "tccutil app-specific reset: failed, exit $result. No retry."
    say "$RESET_OUTPUT"
    stop 'The app-specific reset failed. Do not broaden it or add sudo; share the exact error.'
fi
say "$RESET_OUTPUT"
say ''
say 'Now approve the CURRENT installed copy. Leave RelayBar closed until the final step.'
say '1. In Accessibility, select any old RelayBar row and click minus (-). Skip this if it is absent.'
say '2. Click plus (+). Press Shift-Command-G in the picker and enter:'
say '       ~/Applications/RelayBar.app'
say '3. Add that app and turn its switch ON. Close System Settings afterward.'
say 'Finder also highlights the exact installed app for reference; do not open it yet.'
say 'Do not select a Downloads/build copy or a RelayBar Previous backup.'
/usr/bin/open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility' || stop 'Could not open Accessibility settings. The reset is not repeated.'
/usr/bin/open -R "$APP" || stop 'Could not reveal the installed app in Finder. The reset is not repeated.'
record 'Opened Accessibility settings and revealed the exact installed app.'
printf '\nAfter adding that copy and turning it ON, type OPEN here to launch it (or Return to stop): '
read -r answer || answer=''
[[ "$answer" == 'OPEN' ]] || { record 'Stopped after reset; no app launch requested.'; say 'Stopped. The reset already ran; the app has not been launched by this helper.'; exit 0; }

# Do not launch the executable directly from Terminal: the GUI app must make
# its own in-process trust check after Launch Services opens the bundle.
if /usr/bin/pgrep -x RelayBar >/dev/null 2>&1; then
    stop 'A RelayBar process started during approval. Do not reset again. Quit all copies, then open ~/Applications/RelayBar.app in Finder and read its Native connection report.'
else
    result=$?
    [[ $result -eq 1 ]] || stop 'Cannot verify that no RelayBar copy is running. The reset is not repeated.'
fi
verify_signature
[[ "$(file_hash "$BIN")" == "$BIN_HASH" && "$(file_hash "$PLIST")" == "$PLIST_HASH" ]] || stop 'The installed app changed after approval. No launch was requested; do not repeat the reset blindly.'
record 'Executable and Info.plist hashes after: unchanged; signature re-verified.'
/usr/bin/open -a "$APP" || stop 'Launch Services could not open the installed app. No launch retry was made.'
record 'Launch Services request: accepted for ~/Applications/RelayBar.app.'
record 'Accessibility granted: NOT VERIFIED; obtain the in-app Native connection report.'
say ''
say 'The unchanged 0.9.1 app has been requested through Launch Services.'
say 'RelayBar should return in persistent shell mode. If needed, choose RB -> Return RelayBar Touch Bar, then return to your Sheet.'
say 'Read RB -> Native connection report. The first required result is Accessibility: granted.'
say 'If it is still not granted, stop. Share this recovery report and the in-app report instead of repeating a reset.'
say 'This helper cannot verify permission, browser scanning or the physical Touch Bar.'
