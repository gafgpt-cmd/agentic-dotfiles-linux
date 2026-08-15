#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

config="$ROOT/home/.config/wezterm/wezterm.lua"
raw_bin=${WEZTERM_RAW_BIN:-}

if [ -z "$raw_bin" ]; then
  raw_out=$(dotfiles_nix build --no-link --print-out-paths --impure "path:$ROOT#wezterm-raw") \
    || fail "the raw WezTerm flake package did not build"
  raw_bin="$raw_out/bin/wezterm"
fi

[ -x "$raw_bin" ] || fail "the raw WezTerm binary is not executable"

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
