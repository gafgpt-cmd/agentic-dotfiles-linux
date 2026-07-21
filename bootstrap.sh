#!/usr/bin/env bash
# Takes a fresh Linux machine from nothing to a built home-manager config.
# Run this once. After it finishes, use ./rebuild.sh for every later change.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Linux only. On macOS this used to run far enough to claim ~/.dotfiles (step 2)
# before failing, which silently repointed the nix-darwin repo's edit-in-place
# symlinks at this clone and left Claude Code with no settings at all.
if [ "$(uname -s)" != "Linux" ]; then
  echo "==> This bootstrap is Linux-only (it installs zsh via apt/dnf/pacman and"
  echo "    configures GNOME via dconf); you are on $(uname -s)."
  echo "    For macOS use the nix-darwin repo: github.com/GuillaumeTaffin/dotfiles"
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

echo "==> Step 2: symlink this repo to ~/.dotfiles"
# home.nix resolves its mkOutOfStoreSymlink paths through ~/.dotfiles, so this
# has to exist before the first switch or the build will fail to find them.
ln -sfn "$DIR" ~/.dotfiles

echo "==> Step 3: personalize the configured username"
REAL_USER="$(whoami)"
FLAKE_USER="$(sed -nE 's/^[[:space:]]*user = "([^"]+)";.*/\1/p' "$DIR/flake.nix" | head -n1)"
if [ -z "$FLAKE_USER" ]; then
  echo "    Could not find the single \"user = \" line in flake.nix."
  echo "    Edit flake.nix yourself before continuing."
  exit 1
elif [ "$FLAKE_USER" != "$REAL_USER" ]; then
  echo "    flake.nix is configured for user \"$FLAKE_USER\", but you are \"$REAL_USER\"."
  read -r -p "    Rewrite flake.nix's \"user = \" line to \"$REAL_USER\"? [y/N] " REPLY
  if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
    sed -i -E "s/^([[:space:]]*user = \")[^\"]+(\";.*)/\1${REAL_USER}\2/" "$DIR/flake.nix"
    echo "    Updated. Review the change with: git diff flake.nix"
  else
    echo "    Skipped. Edit the single \"user = \" line in flake.nix yourself before continuing."
    exit 1
  fi
else
  echo "    flake.nix already matches \"$REAL_USER\", nothing to do."
fi

echo "==> Step 4: first home-manager switch (pinned to release-26.05)"
# home-manager doesn't exist yet on a fresh machine, so run it straight from the
# flake this once. After this, rebuild.sh works normally.
# This fetches the home-manager tool from the release-26.05 branch, not the exact
# flake.lock revision. The config it applies is still pinned by this repo's
# flake.lock. No sudo: standalone home-manager only writes to your home dir.
nix run github:nix-community/home-manager/release-26.05 -- \
  switch -b backup --flake ~/.dotfiles#"$REAL_USER"
# If this fails with "nix: command not found", open a new terminal
# (Determinate adds nix to new shells' PATH) and re-run ./bootstrap.sh.

echo "==> Step 5: make zsh the login shell"
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

echo "==> Step 6: verify"
# Assert the end state instead of trusting that every step above did its job.
# Step 6 reports failures itself, so the blanket ERR trap would only add noise.
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

for bin in nvim wezterm herdr claude rg fd fzf jq lazygit starship home-manager; do
  command -v "$bin" >/dev/null 2>&1 && rc=0 || rc=1
  check "$bin installed" "missing from ~/.nix-profile/bin" "$rc"
done

for link in .config/nvim .config/wezterm .config/herdr .claude/settings.json .claude/statusline-command.sh; do
  [ "$(readlink -f "$HOME/$link" 2>/dev/null)" = "$DIR/home/$link" ] && rc=0 || rc=1
  check "~/$link -> repo" "not an edit-in-place symlink into $DIR" "$rc"
done

[ -L "$HOME/.zshrc" ] && rc=0 || rc=1
check "~/.zshrc managed by home-manager" "not a symlink" "$rc"

# The PATH line above is exactly what hid this failure for a whole install: the
# binaries were all there, but no shell hook put them on a real shell's PATH, so
# every check passed while an actual login shell saw none of them. Ask zsh.
ZSH_CHECK="$(find_system_zsh || true)"
if [ -n "$ZSH_CHECK" ]; then
  "$ZSH_CHECK" -ic 'command -v home-manager' >/dev/null 2>&1 </dev/null && rc=0 || rc=1
  check "interactive zsh sees the nix profile" "~/.nix-profile/bin missing from its PATH" "$rc"
fi

LOGIN_SHELL="$(getent passwd "$REAL_USER" | cut -d: -f7)"
[ "$(basename "$LOGIN_SHELL")" = "zsh" ] && rc=0 || rc=1
check "login shell is zsh" "still $LOGIN_SHELL" "$rc"

if [ "$FAILED" != "0" ]; then
  echo
  echo "==> BOOTSTRAP INCOMPLETE. See the FAIL lines above."
  exit 1
fi

echo
echo "==> Done, all checks passed. Log out and back in to land in zsh."
echo "    Use ./rebuild.sh for future changes."
