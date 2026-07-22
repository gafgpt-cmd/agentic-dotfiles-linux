#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Linux only, see the same guard in bootstrap.sh. This claims ~/.dotfiles on
# the very next line, which on macOS hijacks the nix-darwin repo's pointer.
if [ "$(uname -s)" != "Linux" ]; then
  echo "==> This config is Linux-only; you are on $(uname -s)." >&2
  echo "    For macOS use the nix-darwin repo: github.com/GuillaumeTaffin/dotfiles" >&2
  exit 1
fi

ln -sfn "$DIR" ~/.dotfiles

# Never rely on the caller's PATH: a shell that predates the first switch, or one
# where the Nix installer's shell hook never fired, has no home-manager on PATH
# and this would die with "command not found" on an otherwise healthy machine.
PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
# --impure: the flake reads $USER, $HOME, and the CPU arch at switch time, so
# the same clone works on any machine with nothing machine-specific committed.
exec home-manager switch -b backup --impure --flake ~/.dotfiles#default
