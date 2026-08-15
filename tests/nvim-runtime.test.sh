#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(dotfiles_test_tmproot nvim-runtime)
cleanup() { dotfiles_test_cleanup "$TMP_ROOT"; }
trap cleanup EXIT

NVIM_CONFIG="$ROOT/home/.config/nvim"
lock_hash=$(sha256sum "$NVIM_CONFIG/lazy-lock.json" | cut -d' ' -f1)
RUNTIME_CACHE=${NVIM_RUNTIME_CACHE:-"${XDG_CACHE_HOME:-$HOME/.cache}/agentic-dotfiles-tests/nvim/$lock_hash"}
CONFIG_HOME="$TMP_ROOT/config"
STATE_HOME="$TMP_ROOT/state"
CACHE_HOME="$TMP_ROOT/cache"
DATA_HOME="$RUNTIME_CACHE/data"
mkdir -p "$CONFIG_HOME" "$STATE_HOME" "$CACHE_HOME" "$DATA_HOME"
cp -R "$NVIM_CONFIG" "$CONFIG_HOME/nvim"

managed_nvim=$(dotfiles_nix eval --raw --impure \
  "path:$ROOT#homeConfigurations.default.pkgs.neovim.outPath")/bin/nvim
[ -x "$managed_nvim" ] || fail "the managed Neovim binary does not exist"

run_nvim() {
  run_nvim_with_data "$DATA_HOME" "$@"
}

run_nvim_with_data() {
  local data_home=$1
  shift
  timeout 300s env \
    XDG_CONFIG_HOME="$CONFIG_HOME" \
    XDG_DATA_HOME="$data_home" \
    XDG_STATE_HOME="$STATE_HOME" \
    XDG_CACHE_HOME="$CACHE_HOME" \
    "$managed_nvim" "$@"
}

bootstrap_data="$TMP_ROOT/bootstrap-data"
bootstrap_lazy="$bootstrap_data/nvim/lazy/lazy.nvim"
mkdir -p "$bootstrap_lazy"
git -C "$bootstrap_lazy" init -q
printf 'existing checkout\n' >"$bootstrap_lazy/fixture"
git -C "$bootstrap_lazy" add fixture
git -C "$bootstrap_lazy" -c user.name=dotfiles-test -c user.email=dotfiles-test@example.invalid \
  commit -qm fixture
git -C "$bootstrap_lazy" remote add origin https://github.com/folke/lazy.nvim.git
lazy_commit=$(jq -r '."lazy.nvim".commit' "$NVIM_CONFIG/lazy-lock.json")
if git -C "$bootstrap_lazy" cat-file -e "$lazy_commit^{commit}" 2>/dev/null; then
  fail "the existing Lazy fixture already contains the locked commit"
fi
bootstrap_log="$TMP_ROOT/bootstrap.log"
if ! run_nvim_with_data "$bootstrap_data" --headless \
  --cmd "lua package.preload['lazy'] = function() return { setup = function() end } end" \
  +qa >"$bootstrap_log" 2>&1; then
  cat "$bootstrap_log" >&2
  fail "an existing Lazy checkout could not adopt the locked commit"
fi
[ "$(git -C "$bootstrap_lazy" rev-parse HEAD)" = "$lazy_commit" ] \
  || fail "the existing Lazy checkout did not switch to the locked commit"

startup_log="$TMP_ROOT/startup.log"
if ! run_nvim --headless +qa >"$startup_log" 2>&1; then
  cat "$startup_log" >&2
  fail "the migrated Neovim config failed during a fresh locked-plugin startup"
fi
if grep -qi 'deprecated' "$startup_log"; then
  cat "$startup_log" >&2
  fail "the locked Neovim plugins use APIs deprecated by managed Neovim"
fi

while IFS=$'\t' read -r plugin expected; do
  plugin_dir="$DATA_HOME/nvim/lazy/$plugin"
  if [ ! -d "$plugin_dir/.git" ]; then
    cat "$startup_log" >&2
    fail "Lazy did not install locked plugin $plugin"
  fi
  actual=$(git -C "$plugin_dir" rev-parse HEAD)
  [ "$actual" = "$expected" ] \
    || fail "Lazy installed $plugin at $actual instead of locked commit $expected"
done < <(jq -r 'to_entries[] | [.key, .value.commit] | @tsv' "$NVIM_CONFIG/lazy-lock.json")

proof="$TMP_ROOT/config-proof.json"
cat >"$TMP_ROOT/config-proof.lua" <<LUA
vim.api.nvim_exec_autocmds('VimEnter', { modeline = false })
vim.wait(500)
local plugins = require('lazy.core.config').plugins
local missing = {}
for name, plugin in pairs(plugins) do
  if not plugin._.installed then
    table.insert(missing, name)
  end
end
vim.fn.writefile({ vim.json.encode({
  colorscheme = vim.g.colors_name,
  nerd_font = vim.g.have_nerd_font,
  relative_numbers = vim.o.relativenumber,
  plugin_count = vim.tbl_count(plugins),
  missing = missing,
  file_picker_key = vim.fn.maparg('<leader>F', 'n') ~= '',
  project_search_key = vim.fn.maparg('<leader>S', 'n') ~= '',
}) }, '$proof')
LUA
run_nvim --headless "+lua dofile('$TMP_ROOT/config-proof.lua')" +qa \
  >"$TMP_ROOT/config-proof.log" 2>&1 \
  || fail "the migrated Neovim config could not report its runtime state"
jq -e '
  .colorscheme == "tokyonight-night"
  and .nerd_font == true
  and .relative_numbers == true
  and .plugin_count == 26
  and .missing == []
  and .file_picker_key == true
  and .project_search_key == true
' "$proof" >/dev/null || {
  cat "$proof" >&2
  fail "the migrated Neovim runtime state does not match the live configuration"
}

health="$TMP_ROOT/treesitter-health.txt"
run_nvim --headless '+checkhealth nvim-treesitter vim.treesitter' "+silent write! $health" +qa \
  >"$TMP_ROOT/treesitter-health.log" 2>&1 \
  || fail "Neovim could not run the Treesitter health check"
if grep -Eq 'ERROR|Impossible pattern|failed to load' "$health"; then
  grep -E 'ERROR|Impossible pattern|failed to load' "$health" >&2 || true
  fail "the locked Treesitter plugin is incompatible with managed Neovim"
fi

deprecated_health="$TMP_ROOT/deprecated-health.txt"
cat >"$TMP_ROOT/deprecated-proof.lua" <<LUA
for _, lhs in ipairs({ '[d', ']d' }) do
  local mapping = vim.fn.maparg(lhs, 'n', false, true)
  assert(type(mapping.callback) == 'function', 'diagnostic mapping has no callback: ' .. lhs)
  mapping.callback()
end
vim.cmd.checkhealth('vim.deprecated')
vim.cmd('silent write! $deprecated_health')
LUA
run_nvim --headless "+lua dofile('$TMP_ROOT/deprecated-proof.lua')" +qa \
  >"$TMP_ROOT/deprecated-health.log" 2>&1 \
  || fail "Neovim could not run its deprecated-API health check"
if grep -Eq 'WARNING|ERROR' "$deprecated_health"; then
  grep -E 'WARNING|ERROR' "$deprecated_health" >&2 || true
  fail "the locked plugins still call deprecated Neovim APIs"
fi

run_nvim --headless '+MasonToolsInstallSync' +qa \
  >"$TMP_ROOT/mason.log" 2>&1 \
  || fail "Mason could not install the configured Lua tools"

runtime_lua="$CONFIG_HOME/nvim/runtime-proof.lua"
printf 'local x={a=1,b=2}\nprint(x)\n' >"$runtime_lua"
lsp_proof="$TMP_ROOT/lsp-proof.json"
cat >"$TMP_ROOT/lsp-proof.lua" <<LUA
local attached = vim.wait(15000, function()
  return #vim.lsp.get_clients({ bufnr = 0 }) > 0
end, 100)
local clients = {}
local neodev_library = false
for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
  table.insert(clients, client.name)
  if client.name == 'lua_ls' then
    local workspace = client.config.settings and client.config.settings.Lua and client.config.settings.Lua.workspace
    neodev_library = workspace and vim.tbl_count(workspace.library or {}) > 0 or false
  end
end
local ts_ok = pcall(vim.treesitter.start, 0, 'lua')
local parser_ok = pcall(vim.treesitter.get_parser, 0, 'lua')
require('conform').format({ async = false, timeout_ms = 5000 })
vim.cmd('write')
vim.fn.writefile({ vim.json.encode({
  attached = attached,
  clients = clients,
  neodev_library = neodev_library,
  treesitter_highlight = ts_ok,
  treesitter_parser = parser_ok,
}) }, '$lsp_proof')
LUA
run_nvim --headless "$runtime_lua" "+lua dofile('$TMP_ROOT/lsp-proof.lua')" +qa \
  >"$TMP_ROOT/lsp.log" 2>&1 \
  || fail "the configured Lua LSP, formatter, or parser failed"
jq -e '
  .attached == true
  and (.clients | index("lua_ls"))
  and .neodev_library == true
  and .treesitter_highlight == true
  and .treesitter_parser == true
' "$lsp_proof" >/dev/null || {
  cat "$lsp_proof" >&2
  fail "the configured Lua development tools did not become usable"
}
[ "$(<"$runtime_lua")" = $'local x = { a = 1, b = 2 }\nprint(x)' ] \
  || fail "Stylua did not format a Lua buffer"

pass "fresh locked Neovim startup, plugins, Treesitter, Lua LSP, and Stylua all work in isolation"
