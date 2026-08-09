#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SYSTEM="$(nix --extra-experimental-features 'nix-command flakes' eval --raw --impure \
  --expr builtins.currentSystem)"
PROFILES=(default gnome-x11 gnome-wayland xfce-x11 xfce-wayland kde-x11 kde-wayland)
TARGETS=()

for profile in "${PROFILES[@]}"; do
  TARGETS+=("path:$ROOT#checks.$SYSTEM.$profile")
done

nix --extra-experimental-features 'nix-command flakes' build --no-link --impure "${TARGETS[@]}"
