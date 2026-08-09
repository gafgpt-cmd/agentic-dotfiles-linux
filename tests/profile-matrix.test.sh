#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

matrix=$(nix --extra-experimental-features 'nix-command flakes' eval --json --impure \
  "path:$ROOT#lib.profileMatrix")

expected_profiles='["gnome-wayland","gnome-x11","kde-wayland","kde-x11","xfce-wayland","xfce-x11"]'
[ "$(jq -c 'keys' <<<"$matrix")" = "$expected_profiles" ] \
  || fail "flake does not expose the complete desktop/session matrix"

protected=(
  /.zshrc /.zshenv /.profile /.config/starship.toml /.config/nvim /.config/wezterm
  /.config/herdr /.pi/agent /.claude/settings.json /.claude/CLAUDE.md
  /.codex/AGENTS.md /.config/opencode/AGENTS.md
)

for desktop in gnome xfce kde; do
  for session in x11 wayland; do
    profile="$desktop-$session"
    [ "$(jq -r --arg p "$profile" '.[$p].displayServer' <<<"$matrix")" = "$session" ] \
      || fail "$profile exports the wrong display server"
    [ "$(jq -r --arg p "$profile" '.[$p].graphicalDisplayServer' <<<"$matrix")" = "$session" ] \
      || fail "$profile does not export its display server to graphical applications"

    dconf_count=$(jq --arg p "$profile" '.[$p].dconfKeys | length' <<<"$matrix")
    xfconf_count=$(jq --arg p "$profile" '.[$p].xfconfKeys | length' <<<"$matrix")
    gtk_enabled=$(jq -r --arg p "$profile" '.[$p].gtkEnabled' <<<"$matrix")
    plasma_enabled=$(jq -r --arg p "$profile" '.[$p].plasmaEnabled' <<<"$matrix")

    case "$desktop" in
      gnome)
        if ! { [ "$dconf_count" -gt 0 ] && [ "$xfconf_count" -eq 0 ] && [ "$plasma_enabled" = false ]; }; then
          fail "$profile does not isolate GNOME settings"
        fi
        ;;
      xfce)
        dconf_keys=$(jq -r --arg p "$profile" '.[$p].dconfKeys[]' <<<"$matrix")
        if ! { [ "$xfconf_count" -gt 0 ] && [ "$plasma_enabled" = false ] && [ "$gtk_enabled" = true ]; }; then
          fail "$profile does not isolate XFCE settings"
        fi
        assert_not_contains "$dconf_keys" /wm/ "XFCE profile configures GNOME window-manager settings"
        assert_not_contains "$dconf_keys" /shell/ "XFCE profile configures GNOME Shell settings"
        if [ "$session" = wayland ]; then
          xfconf_keys=$(jq -r --arg p "$profile" '.[$p].xfconfKeys[]' <<<"$matrix")
          assert_not_contains "$xfconf_keys" xfwm4 "XFCE Wayland profile configures the X11-only window manager"
          assert_not_contains "$xfconf_keys" xsettings "XFCE Wayland profile configures XSettings"
        fi
        ;;
      kde)
        if ! { [ "$dconf_count" -eq 0 ] && [ "$xfconf_count" -eq 0 ] && [ "$plasma_enabled" = true ]; }; then
          fail "$profile does not isolate KDE settings"
        fi
        [ "$(jq -r --arg p "$profile" '.[$p].plasmaOverrideConfig' <<<"$matrix")" = false ] \
          || fail "$profile can destructively reset existing KDE configuration"
        [ "$(jq -r --arg p "$profile" '.[$p].plasmaLookAndFeel' <<<"$matrix")" = \
          org.kde.breezedark.desktop ] || fail "$profile does not select Breeze Dark"
        ;;
    esac

    managed=$(jq -r --arg p "$profile" '.[$p].managedFiles[]' <<<"$matrix")
    for target in "${protected[@]}"; do
      assert_not_contains "$managed" "$target" "$profile unexpectedly adopts *$target"
    done
  done
done

wezterm=$(cat "$ROOT/home/.config/wezterm/wezterm.lua")
assert_contains "$wezterm" 'display_server == "wayland"' "WezTerm has no Wayland selector"
assert_contains "$wezterm" 'display_server == "x11"' "WezTerm has no X11 selector"
assert_contains "$wezterm" 'config.enable_wayland = true' "WezTerm does not enable native Wayland"
assert_contains "$wezterm" 'config.enable_wayland = false' "WezTerm does not force X11 when selected"

pass "GNOME, XFCE, and KDE isolate settings and evaluate for X11 and Wayland"
