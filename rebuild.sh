#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Linux only -- see the same guard in bootstrap.sh. This claims ~/.dotfiles on
# the very next line, which on macOS hijacks the nix-darwin repo's pointer.
if [ "$(uname -s)" != "Linux" ]; then
  echo "==> This config is Linux-only; you are on $(uname -s)." >&2
  echo "    For macOS use the nix-darwin repo: github.com/GuillaumeTaffin/dotfiles" >&2
  exit 1
fi

ln -sfn "$DIR" ~/.dotfiles
exec home-manager switch -b backup --flake ~/.dotfiles#"$(whoami)"
