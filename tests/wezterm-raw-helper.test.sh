#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

config="$ROOT/home/.config/wezterm/wezterm.lua"
wrapper=${WEZTERM_BIN:-}
raw_bin=${WEZTERM_RAW_BIN:-}

if [ -z "$wrapper" ]; then
  wrapper=$(command -v wezterm || true)
fi
if [ -z "$wrapper" ]; then
  printf 'skip - no WezTerm executable found\n'
  exit 0
fi

if [ -z "$raw_bin" ]; then
  raw_bin=$(python3 - "$wrapper" <<'PY'
import os
import re
import sys

path = os.path.realpath(sys.argv[1])
try:
    data = open(path, "rb").read()
except OSError:
    print("")
    raise SystemExit

if data.startswith(b"\x7fELF") and "/nix/store/" in path and "/bin/wezterm" in path:
    print(path)
    raise SystemExit

text = data.decode(errors="ignore")
matches = re.findall(r'(/nix/store/[^"\s]+-wezterm-[^"\s]+/bin/wezterm)', text)
print(matches[-1] if matches else "")
PY
  )
fi

if [ -z "$raw_bin" ] || [ ! -x "$raw_bin" ]; then
  printf 'skip - no raw Nix WezTerm binary found behind %s\n' "$wrapper"
  exit 0
fi

if ! stderr=$(env \
  -u LIBGL_DRIVERS_PATH \
  -u LD_LIBRARY_PATH \
  RUST_BACKTRACE=1 \
  "$raw_bin" --config-file "$config" show-keys 2>&1 >/dev/null); then
  printf '%s\n' "$stderr" >&2
  fail "raw Nix helper failed while loading the WezTerm config"
fi

panic_marker="called \`Option::unwrap()\` on a \`None\` value"
egl_marker='wgpu-hal-25.0.2/src/gles/egl.rs'
case "$stderr" in
  *"$panic_marker"* | *"$egl_marker"*)
    fail "raw Nix helper panicked in EGL while loading the WezTerm config"
    ;;
esac

pass "raw Nix helper loads the WezTerm config without an EGL panic"
