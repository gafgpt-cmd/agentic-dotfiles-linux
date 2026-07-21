#!/usr/bin/env bash
# Takes a fresh Linux machine from nothing to a built home-manager config.
# Run this once. After it finishes, use ./rebuild.sh for every later change.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

echo "==> Step 1: Determinate Nix"
if command -v nix >/dev/null 2>&1; then
  echo "    nix already installed, skipping"
else
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
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
CURRENT_SHELL="$(getent passwd "$REAL_USER" | cut -d: -f7)"
if [ "$(basename "$CURRENT_SHELL")" = "zsh" ]; then
  echo "    login shell is already $CURRENT_SHELL, nothing to do"
else
  if ! command -v zsh >/dev/null 2>&1; then
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
  fi
  # Resolve after install, and skip Nix's zsh if it happens to be first on PATH.
  ZSH_BIN=""
  for candidate in /usr/bin/zsh /bin/zsh /usr/local/bin/zsh; do
    [ -x "$candidate" ] && ZSH_BIN="$candidate" && break
  done
  if [ -z "$ZSH_BIN" ]; then
    echo "    zsh installed but not found in a system path. Set your shell yourself."
    exit 1
  fi
  # chsh refuses any shell missing from /etc/shells.
  grep -qxF "$ZSH_BIN" /etc/shells || echo "$ZSH_BIN" | sudo tee -a /etc/shells >/dev/null
  sudo chsh -s "$ZSH_BIN" "$REAL_USER"
  echo "    login shell set to $ZSH_BIN (takes effect on your next login)"
fi

echo "==> Done. Use ./rebuild.sh for future changes."
