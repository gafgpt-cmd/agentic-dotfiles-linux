#!/usr/bin/env bash
# Takes a fresh Linux machine from nothing to a built home-manager config.
# Run this once. After it finishes, use ./rebuild.sh for every later change.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Flakes are still experimental in stock Nix. Keep them enabled for both the
# direct `nix run` below and the Nix commands launched by home-manager.
export NIX_CONFIG="${NIX_CONFIG:-}
experimental-features = nix-command flakes"

# Linux only. On macOS this used to run far enough to claim ~/.dotfiles (step 2)
# before failing, which silently repointed the nix-darwin repo's edit-in-place
# symlinks at this clone and left Claude Code with no settings at all.
if [ "$(uname -s)" != "Linux" ]; then
  echo "==> This bootstrap is Linux-only (it installs zsh via apt/dnf/pacman and"
  echo "    applies the selected Linux desktop module); you are on $(uname -s)."
  echo "    For macOS use the nix-darwin repo: github.com/kunchenguid/dotfiles"
  exit 1
fi

# A mid-script failure otherwise scrolls past in the build output and looks like
# success. Make it impossible to miss.
trap 'echo; echo "==> BOOTSTRAP FAILED at line $LINENO. The machine is only partly set up."; echo "    Fix the error above and re-run ./bootstrap.sh - it is safe to run again."' ERR

echo "==> Step 1: Determinate Nix"
NIX_PROFILE_SCRIPT=/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
# Only login shells get nix on PATH, so `ssh host ./bootstrap.sh`, cron, or any
# non-login shell would see no nix and try to reinstall it over a working one.
# Test the profile on disk, not the PATH.
if [ -e "$NIX_PROFILE_SCRIPT" ]; then
  # shellcheck disable=SC1090
  . "$NIX_PROFILE_SCRIPT"
fi
if command -v nix >/dev/null 2>&1; then
  echo "    nix already installed, skipping"
else
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
  # shellcheck disable=SC1090
  . "$NIX_PROFILE_SCRIPT"
fi

# --impure: pure evaluation forbids reading a path outside the store, so a plain
# `nix eval` on ./profile.nix aborts the whole bootstrap before step 2.
profile_enabled() {
  (cd "$DIR" && nix eval --impure --raw --expr "if (import ./profile.nix).$1 then \"1\" else \"0\"")
}
MANAGE_SHELL="$(profile_enabled manageShell)"

echo "==> Step 2: symlink this repo to ~/.dotfiles"
# home.nix resolves its mkOutOfStoreSymlink paths through ~/.dotfiles, so this
# has to exist before the first switch or the build will fail to find them.
if [ -L "$HOME/.dotfiles" ] && [ "$(readlink -f "$HOME/.dotfiles")" = "$DIR" ]; then
  echo "    $HOME/.dotfiles already points here, skipping"
elif [ -e "$HOME/.dotfiles" ] || [ -L "$HOME/.dotfiles" ]; then
  echo "    Refusing to replace existing $HOME/.dotfiles. Move it yourself or use that repo." >&2
  exit 1
else
  ln -s "$DIR" "$HOME/.dotfiles"
fi

echo "==> Step 3: first home-manager switch (pinned to release-26.05)"
REAL_USER="$(whoami)"
# home-manager doesn't exist yet on a fresh machine, so run it straight from the
# flake this once. After this, rebuild.sh works normally.
# This fetches the home-manager tool from the release-26.05 branch, not the exact
# flake.lock revision. The config it applies is still pinned by this repo's
# flake.lock. No sudo: standalone home-manager only writes to your home dir.
# --impure: the flake reads $USER, $HOME, and the CPU arch from the environment
# so nothing machine-specific is ever committed to this repo.
nix run github:nix-community/home-manager/release-26.05 -- \
  switch -b backup --impure --flake ~/.dotfiles#default
# If this fails with "nix: command not found", open a new terminal
# (Determinate adds nix to new shells' PATH) and re-run ./bootstrap.sh.

echo "==> Step 4: make zsh the login shell"
# home-manager owns ~/.zshrc but cannot set the login shell outside NixOS, and
# /etc/passwd is root-owned, so this needs the distro package manager + sudo.
# Deliberately the distro's zsh, not Nix's: /usr/bin/zsh always exists, so a
# broken home-manager generation can never lock you out of an SSH login.
# Never `command -v zsh` here: home-manager puts Nix's zsh on PATH, which would
# make the check pass and skip the distro install we actually need.
find_system_zsh() {
  for candidate in /usr/bin/zsh /bin/zsh /usr/local/bin/zsh; do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

if [ "$MANAGE_SHELL" != "1" ]; then
  echo "    skipped: profile.manageShell is false; existing shell files and login shell stay untouched"
else
  CURRENT_SHELL="$(getent passwd "$REAL_USER" | cut -d: -f7)"
  if [ "$(basename "$CURRENT_SHELL")" = "zsh" ]; then
    echo "    login shell is already $CURRENT_SHELL, nothing to do"
  else
    ZSH_BIN="$(find_system_zsh || true)"
    if [ -z "$ZSH_BIN" ]; then
      echo "    installing zsh"
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq && sudo apt-get install -y zsh
      elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y zsh
      elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm zsh
      else
        echo "    Unknown package manager. Install zsh yourself, then re-run ./bootstrap.sh."
        exit 1
      fi
      ZSH_BIN="$(find_system_zsh || true)"
    fi
    if [ -z "$ZSH_BIN" ]; then
      echo "    zsh installed but not found in a system path. Set your shell yourself."
      exit 1
    fi
    # chsh refuses any shell missing from /etc/shells.
    grep -qxF "$ZSH_BIN" /etc/shells || echo "$ZSH_BIN" | sudo tee -a /etc/shells >/dev/null
    sudo chsh -s "$ZSH_BIN" "$REAL_USER"
    echo "    login shell set to $ZSH_BIN (takes effect on your next login)"
  fi
fi

echo "==> Step 5: verify"
# Assert the end state instead of trusting that every step above did its job.
# Step 5 reports failures itself, so the blanket ERR trap would only add noise.
trap - ERR
# The current shell predates the switch, so reach into the profile directly.
PATH="$HOME/.nix-profile/bin:$PATH"
FAILED=0
check() { # check <label> <condition-description> <0|1 ok>
  if [ "$3" = "0" ]; then
    printf '    ok    %s\n' "$1"
  else
    printf '    FAIL  %s (%s)\n' "$1" "$2"
    FAILED=1
  fi
}

VERIFY_BINS=(nvim wezterm herdr claude pi git gh tmux mise uv tsc shellcheck shfmt rg fd fzf jq lazygit mosh mosh-server home-manager)
[ "$MANAGE_SHELL" = "1" ] && VERIFY_BINS+=(starship)
for bin in "${VERIFY_BINS[@]}"; do
  command -v "$bin" >/dev/null 2>&1 && rc=0 || rc=1
  check "$bin installed" "missing from ~/.nix-profile/bin" "$rc"
done

# Ask the configuration which files it adopts, and what each one should be,
# instead of restating home.nix here: a hand-kept copy of that list silently
# stops covering every new home.file declaration. Nix's own diagnostic is left
# on the console so a failure here says why.
ADOPTED_FILES="$(nix eval --impure --raw "path:$DIR#homeConfigurations.default.config.home.file" \
  --apply 'fs: builtins.concatStringsSep "\n" (map (f: f.target + "\t" + f.source) (builtins.filter (f: f.enable) (builtins.attrValues fs)))' \
  || true)"
if [ -z "$ADOPTED_FILES" ]; then
  check "adopted file list" "could not evaluate home.file from $DIR" 1
fi
while IFS="$(printf '\t')" read -r target source; do
  target="${target#./}"
  [ -n "$target" ] || continue
  # Both sides are fully resolved, so an edit-in-place link lands on the same
  # repo file and a generated one lands on the same store path.
  expected="$(readlink -f "$source" 2>/dev/null || true)"
  resolved="$(readlink -f "$HOME/$target" 2>/dev/null || true)"
  { [ -n "$expected" ] && [ "$resolved" = "$expected" ]; } && rc=0 || rc=1
  check "$HOME/$target -> ${expected:-$source}" "resolves to '$resolved' instead" "$rc"
done <<ADOPTED
$ADOPTED_FILES
ADOPTED

if [ "$MANAGE_SHELL" = "1" ]; then
  [ -L "$HOME/.zshrc" ] && rc=0 || rc=1
  check "$HOME/.zshrc managed by home-manager" "not a symlink" "$rc"

  # Ask a real interactive shell rather than trusting the current process PATH.
  ZSH_CHECK="$(find_system_zsh || true)"
  if [ -n "$ZSH_CHECK" ]; then
    "$ZSH_CHECK" -ic 'command -v home-manager' >/dev/null 2>&1 </dev/null && rc=0 || rc=1
    check "interactive zsh sees the nix profile" "$HOME/.nix-profile/bin missing from its PATH" "$rc"
  fi

  LOGIN_SHELL="$(getent passwd "$REAL_USER" | cut -d: -f7)"
  [ "$(basename "$LOGIN_SHELL")" = "zsh" ] && rc=0 || rc=1
  check "login shell is zsh" "still $LOGIN_SHELL" "$rc"
fi

if [ "$FAILED" != "0" ]; then
  echo
  echo "==> BOOTSTRAP INCOMPLETE. See the FAIL lines above."
  exit 1
fi

echo
if [ "$MANAGE_SHELL" = "1" ]; then
  echo "==> Done, all checks passed. Log out and back in to land in zsh."
else
  echo "==> Done, all checks passed. Existing shell and app configs were not adopted."
fi
echo "    Use ./rebuild.sh for future changes."
