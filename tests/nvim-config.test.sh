#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

NVIM_DIR="$ROOT/home/.config/nvim"

for file in \
  init.lua \
  lazy-lock.json \
  .stylua.toml \
  LICENSE.md \
  lua/kickstart/health.lua \
  lua/kickstart/plugins/debug.lua \
  lua/kickstart/plugins/indent_line.lua \
  lua/kickstart/plugins/lint.lua \
  lua/custom/plugins/init.lua; do
  [ -f "$NVIM_DIR/$file" ] || fail "the migrated Neovim config is missing $file"
done

jq -e '
  length == 26
  and .["lazy.nvim"].commit != null
  and .["mason.nvim"].commit != null
  and .["nvim-lspconfig"].commit != null
  and .["nvim-treesitter"].branch == "master"
' "$NVIM_DIR/lazy-lock.json" >/dev/null \
  || fail "the migrated Neovim lock does not pin the complete Kickstart plugin set"

if git -C "$ROOT" ls-files --error-unmatch 'home/.config/nvim/.git/*' >/dev/null 2>&1; then
  fail "nested Neovim git metadata was committed"
fi

pass "the authored Kickstart config and its complete plugin lock are reproducible without runtime state"
