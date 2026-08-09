#!/usr/bin/env bash
# tests/lib.sh - shared primitives for dotfiles behavior tests.
#
# Source this from a test file:
#   # shellcheck source=tests/lib.sh
#   . "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# ROOT is exported as the repository root (this file lives in tests/).

if [ -n "${DOTFILES_TEST_LIB_SOURCED:-}" ]; then
  return 0
fi
DOTFILES_TEST_LIB_SOURCED=1

# shellcheck disable=SC2034
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

# --- trash-aware temp root ---------------------------------------------------

dotfiles_test_cleanup() {
  local d destination
  for d in "$@"; do
    [ -d "$d" ] || continue
    if ! command -v gio >/dev/null 2>&1; then
      printf 'kept disposable test evidence (gio unavailable): %s\n' "$d" >&2
      continue
    fi
    destination="$HOME/.$(basename "$d").$$"
    if [ -e "$destination" ]; then
      printf 'kept disposable test evidence (trash staging exists): %s\n' "$d" >&2
      continue
    fi
    mv "$d" "$destination"
    if ! gio trash "$destination"; then
      printf 'kept disposable test evidence (trash failed): %s\n' "$destination" >&2
    fi
  done
}

dotfiles_test_tmproot() {
  local prefix=${1:-dotfiles-test}
  mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX"
}

# --- assertions ---------------------------------------------------------------

assert_contains() {
  local haystack=$1 needle=$2 message=$3
  case "$haystack" in
    *"$needle"*) : ;;
    *) fail "$message" ;;
  esac
}

assert_not_contains() {
  local haystack=$1 needle=$2 message=$3
  case "$haystack" in
    *"$needle"*) fail "$message" ;;
    *) : ;;
  esac
}

# --- Home Manager ownership ----------------------------------------------------

# Paths the user keeps unless a profile switch explicitly adopts them.
# shellcheck disable=SC2034
DOTFILES_PROTECTED_PATHS=(
  .zshrc .zshenv .profile .config/starship.toml .config/nvim .config/wezterm
  .config/herdr .pi/agent .claude/settings.json .claude/CLAUDE.md
  .codex/AGENTS.md .config/opencode/AGENTS.md .config/kdeglobals
)

# The subset this repo can adopt, used as a positive control so the guard over
# DOTFILES_PROTECTED_PATHS is proven able to fail.
# shellcheck disable=SC2034
DOTFILES_ADOPTABLE_PATHS=(
  .zshrc .zshenv .config/starship.toml .config/nvim .config/wezterm
  .config/herdr .pi/agent .claude/settings.json .claude/CLAUDE.md
  .codex/AGENTS.md .config/opencode/AGENTS.md
)

dotfiles_nix() {
  nix --extra-experimental-features 'nix-command flakes' "$@"
}

# Echoes a Nix expression for this repo's configuration with profile overrides,
# e.g. dotfiles_hm_profile 'managePiResources = true;'
dotfiles_hm_profile() {
  printf '(builtins.getFlake "path:%s").homeConfigurations.default.extendModules { specialArgs.profile = (import %s/profile.nix) // { %s }; }' \
    "$ROOT" "$ROOT" "${1:-}"
}

# Home Manager keeps declared keys as written (".config/nvim", "./.zshrc", or an
# absolute path) but normalizes every entry's target to a home-relative path.
# Reads a JSON array of targets on stdin, echoes the comparable form.
dotfiles_normalize_targets() {
  jq -c 'map(sub("^\\./"; "")) | sort'
}

dotfiles_hm_targets() {
  dotfiles_nix eval --json --impure \
    --expr "map (f: f.target) (builtins.attrValues ($1).config.home.file)" \
    | dotfiles_normalize_targets
}

# Home Manager owns a path when it manages that exact target, anything below it,
# or any ancestor of it: managing ~/.pi/agent adopts ~/.pi/agent/calm with it.
dotfiles_owns() {
  local targets=$1 path=$2
  jq -e --arg p "$path" '
    map(select(. as $t |
      $t == $p or ($t | startswith($p + "/")) or ($p | startswith($t + "/"))))
    | length > 0
  ' >/dev/null <<<"$targets"
}

# --- deterministic git fixtures ------------------------------------------------

dotfiles_git_init_commit() {
  local dir=$1
  mkdir -p "$dir"
  git -C "$dir" init -q
  printf '# %s\n' "$(basename "$dir")" > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" -c user.name=dotfiles-test -c user.email=dotfiles-test@example.invalid \
    commit -qm "fixture"
}
