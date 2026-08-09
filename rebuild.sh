#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# home-manager launches Nix internally; stock Nix needs flakes enabled there.
export NIX_CONFIG="${NIX_CONFIG:-}
experimental-features = nix-command flakes"

# Linux only, see the same guard in bootstrap.sh. This claims ~/.dotfiles on
# the very next line, which on macOS hijacks the nix-darwin repo's pointer.
if [ "$(uname -s)" != "Linux" ]; then
  echo "==> This config is Linux-only; you are on $(uname -s)." >&2
  echo "    For macOS use the nix-darwin repo: github.com/kunchenguid/dotfiles" >&2
  exit 1
fi

if [ -L "$HOME/.dotfiles" ] && [ "$(readlink -f "$HOME/.dotfiles")" = "$DIR" ]; then
  :
elif [ -e "$HOME/.dotfiles" ] || [ -L "$HOME/.dotfiles" ]; then
  echo "Refusing to replace existing $HOME/.dotfiles. Move it yourself or use that repo." >&2
  exit 1
else
  ln -s "$DIR" "$HOME/.dotfiles"
fi

# Never rely on the caller's PATH: a shell that predates the first switch, or one
# where the Nix installer's shell hook never fired, has no home-manager on PATH
# and this would die with "command not found" on an otherwise healthy machine.
PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
# --impure: the flake reads $USER, $HOME, and the CPU arch at switch time, so
# the same clone works on any machine with nothing machine-specific committed.
exec home-manager switch -b backup --impure --flake ~/.dotfiles#default
