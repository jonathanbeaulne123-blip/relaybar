#!/bin/bash
# RelayBar build-only toolchain compatibility. Source this from a script that
# sets -euo pipefail. Bash 3.2 compatible; no downloads or system-file writes.

rb_json_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '"%s"' "$value"
}

rb_known_bridging_map() {
  # Intentionally narrow: only Apple's single, simple SwiftBridging definition.
  # Unknown declarations/comments/extra modules are NOT discarded or rewritten.
  [[ -f "$1" && ! -L "$1" ]] || return 1
  local normalized
  normalized="$(LC_ALL=C awk '!/^[[:space:]]*\/\// {gsub(/[[:space:]]/, ""); printf "%s", $0}' "$1")" || return 1
  [[ "$normalized" == 'moduleSwiftBridging{header"bridging"export*}' ]]
}

rb_create_bridging_overlay() {
  # Arguments are a previously identified include/swift directory and a NEW
  # project-local output directory. Real developer tools remain read-only.
  local include_dir="$1" out="$2" old current shim
  old="$include_dir/module.modulemap"
  current="$include_dir/bridging.modulemap"
  [[ -d "$include_dir" && -f "$include_dir/bridging" && ! -L "$include_dir/bridging" ]] || return 1
  rb_known_bridging_map "$old" || return 1
  rb_known_bridging_map "$current" || return 1
  [[ ! -e "$out" && ! -L "$out" ]] || return 1
  mkdir -m 700 "$out" || return 1
  shim="$out/empty-legacy.modulemap"
  printf '// RelayBar compile-only view. The real SwiftBridging definition remains in bridging.modulemap.\n' > "$shim" || return 1
  RB_VFS="$out/overlay.json"
  RB_BRIDGING_MAP="$current"
  {
    printf '{"version":0,"case-sensitive":false,"use-external-names":false,"roots":['
    printf '{"type":"file","name":'; rb_json_quote "$old"
    printf ',"external-contents":'; rb_json_quote "$shim"
    printf '}]}\n'
  } > "$RB_VFS" || return 1
  chmod 600 "$shim" "$RB_VFS" || return 1
}

rb_set_flags() {
  local cache="$1"
  mkdir -p "$cache" || return 1
  RB_SWIFT_FLAGS=(-sdk "$RB_SDK" -module-cache-path "$cache")
  RB_CLANG_FLAGS=(-isysroot "$RB_SDK" "-fmodules-cache-path=$cache")
  if [[ -n "${RB_VFS:-}" ]]; then
    RB_SWIFT_FLAGS+=(-vfsoverlay "$RB_VFS" -Xcc -ivfsoverlay -Xcc "$RB_VFS" -Xcc "-fmodule-map-file=$RB_BRIDGING_MAP")
    RB_CLANG_FLAGS+=(-ivfsoverlay "$RB_VFS" "-fmodule-map-file=$RB_BRIDGING_MAP")
  fi
}

rb_prepare_toolchain() {
  RB_ROOT="$1"
  [[ "$(uname -s)" == "Darwin" ]] || { echo 'This check requires macOS.' >&2; return 2; }
  umask 077
  # Respect an explicit developer directory, but do not combine an inherited
  # SDK or third-party header search paths with the selected Apple toolchain.
  DEVELOPER_DIR="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}" || return 2
  [[ -d "$DEVELOPER_DIR" ]] || { echo 'The selected developer directory is missing.' >&2; return 2; }
  export DEVELOPER_DIR
  unset SDKROOT TOOLCHAINS CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH LIBRARY_PATH
  unset SWIFT_EXEC SWIFT_EXEC_MANIFEST
  RB_SWIFTC="$(/usr/bin/xcrun --toolchain default --sdk macosx --find swiftc)" || return 2
  RB_CLANG="$(/usr/bin/xcrun --toolchain default --sdk macosx --find clang)" || return 2
  RB_SWIFT="$(/usr/bin/xcrun --toolchain default --sdk macosx --find swift)" || return 2
  RB_SDK="$(/usr/bin/xcrun --toolchain default --sdk macosx --show-sdk-path)" || return 2
  RB_BIN="$(cd "$(dirname "$RB_SWIFTC")" && pwd -P)" || return 2
  export SDKROOT="$RB_SDK"
  export PATH="$RB_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
  mkdir -p "$RB_ROOT/build/runs" || return 2
  RB_RUN="$(mktemp -d "$RB_ROOT/build/runs/run.XXXXXX")" || return 2
  RB_VFS=""; RB_BRIDGING_MAP=""; RB_INCLUDE=""
  if [[ -d "$RB_BIN/../include/swift" ]]; then
    RB_INCLUDE="$(cd "$RB_BIN/../include/swift" && pwd -P)" || return 2
  fi
  {
    printf 'RelayBar 0.1.1 — build environment\n'
    /usr/bin/sw_vers
    printf 'Architecture: '; uname -m
    printf 'Developer directory: %s\nSwift: %s\nClang: %s\nSDK: %s\n' "$DEVELOPER_DIR" "$RB_SWIFTC" "$RB_CLANG" "$RB_SDK"
    "$RB_SWIFTC" --version
    "$RB_CLANG" --version
    /usr/sbin/pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null || true
    printf 'Inherited SDK/header overrides ignored for this process only.\n'
    if [[ -n "$RB_INCLUDE" ]]; then
      local map
      for map in "$RB_INCLUDE/module.modulemap" "$RB_INCLUDE/bridging.modulemap"; do
        if [[ -f "$map" ]]; then /usr/bin/shasum -a 256 "$map"; fi
      done
    fi
  } | tee "$RB_RUN/environment.txt"
}

rb_probe() {
  local arch="$1" log="$2"
  "$RB_SWIFTC" "${RB_SWIFT_FLAGS[@]}" -swift-version 5 \
    -target "$arch-apple-macosx12.0" -typecheck \
    -import-objc-header "$RB_ROOT/Sources/Bridge/NativeBridge.h" \
    "$RB_ROOT/Scripts/CompileProbe.swift" > "$log" 2>&1
}

rb_preflight() {
  local arch="$1" baseline retry
  baseline="$RB_RUN/preflight-$arch-baseline.log"
  retry="$RB_RUN/preflight-$arch-compatibility.log"
  rb_set_flags "$RB_RUN/cache-$arch-baseline" || return 2
  printf '\nChecking Cocoa and the Objective-C bridge for %s…\n' "$arch"
  if rb_probe "$arch" "$baseline"; then
    if [[ -n "${RB_VFS:-}" ]]; then
      printf 'PASS: compiler probe with the project-local compatibility view.\n'
    else
      printf 'PASS: compiler probe without a workaround.\n'
    fi
    return 0
  fi
  # Only attempt the workaround for the exact reported duplicate pair in this
  # selected toolchain. Never mask an unfamiliar module or another toolchain.
  if [[ -z "${RB_VFS:-}" && -n "$RB_INCLUDE" ]] && \
     grep -Fq "redefinition of module 'SwiftBridging'" "$baseline" && \
     grep -Fq "$RB_INCLUDE/module.modulemap:" "$baseline" && \
     grep -Fq "$RB_INCLUDE/bridging.modulemap:" "$baseline"; then
    printf 'Detected the duplicate SwiftBridging map from the reported failure.\n'
    if rb_create_bridging_overlay "$RB_INCLUDE" "$RB_RUN/compatibility"; then
      printf 'Trying a project-local compiler view; no Apple files were changed.\n'
      rb_set_flags "$RB_RUN/cache-$arch-compatibility" || return 2
      if rb_probe "$arch" "$retry"; then
        printf 'PASS: compiler probe with the project-local compatibility view.\n'
        return 0
      fi
      printf 'The compatibility retry failed. The app has not been installed.\n' >&2
      sed -n '1,32p' "$retry" >&2
      printf 'Full retry log: %s\n' "$retry" >&2
    else
      printf 'The map contents are unfamiliar or unsafe to mask. No workaround was applied.\n' >&2
    fi
  else
    printf 'This is not the exact duplicate-map case, or an active workaround did not pass.\n' >&2
  fi
  printf '\nFirst compiler diagnostics:\n' >&2
  sed -n '1,28p' "$baseline" >&2
  printf '\nFull compiler log: %s\nEnvironment: %s\n' "$baseline" "$RB_RUN/environment.txt" >&2
  printf 'No global caches were cleared; no developer-tool files or installed app were edited by this check.\n' >&2
  printf 'Keep these logs. Do not delete CommandLineTools or disable Mac security.\n' >&2
  return 2
}
