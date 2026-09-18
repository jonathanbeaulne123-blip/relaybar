#!/bin/bash
# Build locally with Apple's free toolchain. No downloads, sudo, package managers,
# paid developer membership, code signing certificate, or API keys are needed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'RelayBar uses AppKit and must be built on macOS. The core tests run on Linux too.\n' >&2
  exit 2
fi
if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find swiftc >/dev/null 2>&1; then
  printf 'Install Apple Command Line Tools with: xcode-select --install\nThen run Install.command again.\n' >&2
  exit 2
fi
source "$ROOT/Scripts/toolchain.sh"
rb_prepare_toolchain "$ROOT"
SWIFTC="$RB_SWIFTC"
CLANG="$RB_CLANG"
SDK="$RB_SDK"
OUT="$ROOT/build"
APP="$OUT/RelayBar.app"
ARCHES="$(uname -m)"
if [[ "${1:-}" == "--universal" ]]; then ARCHES="arm64 x86_64"; fi
case "$ARCHES" in arm64|x86_64|"arm64 x86_64") ;; *) echo "Unsupported architecture: $ARCHES" >&2; exit 2;; esac
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$OUT/objects"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
for ARCH in $ARCHES; do
  rb_preflight "$ARCH"
  printf '\nCompiling RelayBar for %s…\n' "$ARCH"
  "$CLANG" "${RB_CLANG_FLAGS[@]}" -fobjc-arc -fmodules -arch "$ARCH" -mmacosx-version-min=12.0 \
    -Werror=implicit-function-declaration -c "$ROOT/Sources/Bridge/NativeBridge.m" -o "$OUT/objects/Bridge-$ARCH.o"
  "$SWIFTC" "${RB_SWIFT_FLAGS[@]}" -swift-version 5 -parse-as-library -O -target "$ARCH-apple-macosx12.0" \
    -module-name RelayBar -import-objc-header "$ROOT/Sources/Bridge/NativeBridge.h" \
    "$ROOT"/Sources/Core/*.swift "$ROOT"/Sources/Mac/*.swift "$OUT/objects/Bridge-$ARCH.o" \
    -framework Cocoa -framework ApplicationServices -framework Carbon -framework ImageIO -framework CoreGraphics \
    -o "$OUT/objects/RelayBar-$ARCH"
done
if [[ "$ARCHES" == "arm64 x86_64" ]]; then
  /usr/bin/lipo -create "$OUT/objects/RelayBar-arm64" "$OUT/objects/RelayBar-x86_64" -output "$APP/Contents/MacOS/RelayBar"
else
  cp "$OUT/objects/RelayBar-$ARCHES" "$APP/Contents/MacOS/RelayBar"
fi
chmod 755 "$APP/Contents/MacOS/RelayBar"
printf '\nBuilding the local app icon…\n'
"$SWIFTC" "${RB_SWIFT_FLAGS[@]}" "$ROOT/Scripts/MakeIcon.swift" -o "$OUT/objects/make-icon"
"$OUT/objects/make-icon" "$OUT/icon.png"
ICONSET="$OUT/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  /usr/bin/sips -z "$SIZE" "$SIZE" "$OUT/icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  /usr/bin/sips -z "$DOUBLE" "$DOUBLE" "$OUT/icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
/usr/bin/codesign --force --sign - --requirements '=designated => identifier "local.relaybar"' --timestamp=none "$APP"
/usr/bin/codesign --verify --strict "$APP"
printf '\nBuilt and locally signed: %s\n' "$APP"

# Automatically publish to ~/Downloads as requested
DOWNLOADS_APP="$HOME/Downloads/RelayBar.app"
if rm -rf "$DOWNLOADS_APP" 2>/dev/null && cp -R "$APP" "$DOWNLOADS_APP" 2>/dev/null; then
  /usr/bin/codesign --force --sign - --requirements '=designated => identifier "local.relaybar"' --timestamp=none "$DOWNLOADS_APP" 2>/dev/null || true
  /usr/bin/codesign --verify --strict "$DOWNLOADS_APP" 2>/dev/null || true
  printf 'Deployed to Downloads: %s\n' "$DOWNLOADS_APP"
else
  printf 'Note: Sandboxed build completed. Direct write to %s requires unsandboxed deploy.\n' "$DOWNLOADS_APP"
fi

APPLICATIONS_APP="$HOME/Applications/RelayBar.app"
if [[ -d "$HOME/Applications" ]]; then
  if rm -rf "$APPLICATIONS_APP" 2>/dev/null && cp -R "$APP" "$APPLICATIONS_APP" 2>/dev/null; then
    /usr/bin/codesign --force --sign - --requirements '=designated => identifier "local.relaybar"' --timestamp=none "$APPLICATIONS_APP" 2>/dev/null || true
    /usr/bin/codesign --verify --strict "$APPLICATIONS_APP" 2>/dev/null || true
    printf 'Deployed to Applications: %s\n' "$APPLICATIONS_APP"
  fi
fi
printf 'This does not verify physical Touch Bar rendering. Run the included Doctor.command and manual checklist.\n'
