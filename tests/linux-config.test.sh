#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

for script in "$ROOT/bootstrap.sh" "$ROOT/rebuild.sh" "$ROOT/home/.claude/statusline-command.sh"; do
  bash -n "$script" || fail "$(basename "$script") has invalid shell syntax"
done

shellcheck "$ROOT/bootstrap.sh" "$ROOT/rebuild.sh" "$ROOT/home/.claude/statusline-command.sh" \
  || fail "shellcheck failed"

home_nix=$(cat "$ROOT/home.nix")
profile_nix=$(cat "$ROOT/profile.nix")
bootstrap=$(cat "$ROOT/bootstrap.sh")

assert_contains "$home_nix" 'profile.desktop == "xfce"' "XFCE profile is not wired"
assert_contains "$home_nix" 'profile.desktop == "gnome"' "GNOME profile is not wired"
assert_contains "$profile_nix" 'desktop = "none";' "safe profile changes desktop settings"
for switch in manageShell manageNvim manageWezterm manageHerdr managePiResources \
  manageClaudeSettings manageAgentInstructions; do
  assert_contains "$profile_nix" "$switch = false;" "$switch is not safe by default"
  assert_contains "$home_nix" "profile.$switch" "$switch is not wired"
done
assert_contains "$home_nix" 'pi-pkg' "the tested Pi package is not installed by Home Manager"
assert_contains "$home_nix" 'GNHF_TELEMETRY = "0";' "GNHF telemetry is not disabled"
assert_contains "$home_nix" 'NO_MISTAKES_TELEMETRY = "0";' "no-mistakes telemetry is not disabled"
assert_contains "$home_nix" 'LAVISH_AXI_TELEMETRY = "0";' "Lavish telemetry is not disabled"
assert_contains "$home_nix" 'PI_TELEMETRY = "0";' "Pi telemetry is not disabled"
assert_contains "$home_nix" 'PI_SKIP_VERSION_CHECK = "1";' "Pi version check is not disabled"
assert_contains "$home_nix" 'DISABLE_TELEMETRY = "1";' "Claude telemetry is not disabled"
assert_contains "$home_nix" 'DISABLE_ERROR_REPORTING = "1";' "Claude error reporting is not disabled"
for flag in DO_NOT_TRACK DISABLE_TELEMETRY DISABLE_ERROR_REPORTING \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC OTEL_SDK_DISABLED \
  OTEL_TRACES_EXPORTER OTEL_METRICS_EXPORTER OTEL_LOGS_EXPORTER \
  PI_TELEMETRY PI_SKIP_VERSION_CHECK \
  HOMEBREW_NO_ANALYTICS NEXT_TELEMETRY_DISABLED ASTRO_TELEMETRY_DISABLED \
  TURBO_TELEMETRY_DISABLED DOTNET_CLI_TELEMETRY_OPTOUT \
  POWERSHELL_TELEMETRY_OPTOUT CHECKPOINT_DISABLE SCARF_NO_ANALYTICS \
  HF_HUB_DISABLE_TELEMETRY DVC_NO_ANALYTICS; do
  assert_contains "$home_nix" "$flag" "$flag is not set"
done
assert_contains "$(cat "$ROOT/home/.pi/agent/settings.json")" '"enableInstallTelemetry": false' \
  "Pi install telemetry is not disabled in settings"
assert_contains "$(cat "$ROOT/home/.pi/agent/settings.json")" '"enableAnalytics": false' \
  "Pi analytics is not disabled in settings"
assert_contains "$home_nix" 'disableCodexTelemetry' "Codex config telemetry gate is not activated"
assert_contains "$home_nix" 'systemd.user.sessionVariables = privacyVariables;' \
  "graphical apps do not inherit privacy controls"
assert_contains "$(cat "$ROOT/scripts/ensure-codex-privacy.py")" 'analytics["enabled"] = False' \
  "Codex analytics is not explicitly disabled"
assert_contains "$(cat "$ROOT/scripts/ensure-codex-privacy.py")" 'otel["metrics_exporter"] = "none"' \
  "Codex metrics export is not explicitly disabled"
assert_contains "$(cat "$ROOT/README.md")" 'Telemetry is off across the managed stack.' \
  "telemetry policy is undocumented"
assert_not_contains "$home_nix" 'dangerously-skip-permissions' "unsafe Claude alias returned"
assert_not_contains "$home_nix" 'codex --full-auto' "unsafe Codex alias returned"
assert_contains "$bootstrap" 'github.com/kunchenguid/dotfiles' "macOS fallback does not point to current upstream"
assert_not_contains "$bootstrap" 'ln -sfn' "bootstrap can overwrite an existing dotfiles pointer"
assert_not_contains "$(cat "$ROOT/rebuild.sh")" 'ln -sfn' "rebuild can overwrite an existing dotfiles pointer"
assert_contains "$bootstrap" 'experimental-features = nix-command flakes' "bootstrap does not enable flakes"
assert_contains "$(cat "$ROOT/rebuild.sh")" 'experimental-features = nix-command flakes' \
  "rebuild does not enable flakes for home-manager"

jq -e . "$ROOT/home/.claude/settings.json" "$ROOT/home/.pi/agent/models.json" \
  "$ROOT/home/.pi/agent/settings.json" "$ROOT/home/.pi/agent/themes/rose-pine-moon.json" >/dev/null \
  || fail "managed JSON is invalid"

managed_files=$(nix --extra-experimental-features 'nix-command flakes' eval --json --impure \
  "path:$ROOT#homeConfigurations.default.config.home.file" --apply builtins.attrNames | jq -r '.[]')
for target in .zshrc .zshenv .profile .config/starship.toml .config/nvim .config/wezterm \
  .config/herdr .pi/agent .claude/settings.json .claude/CLAUDE.md .codex/AGENTS.md \
  .config/opencode/AGENTS.md; do
  assert_not_contains "$managed_files" "/$target" "safe profile unexpectedly owns ~/$target"
done
[ "$(nix --extra-experimental-features 'nix-command flakes' eval --json --impure \
  "path:$ROOT#homeConfigurations.default.config.xfconf.settings")" = '{}' ] \
  || fail "safe profile changes XFCE settings"
[ "$(nix --extra-experimental-features 'nix-command flakes' eval --json --impure \
  "path:$ROOT#homeConfigurations.default.config.dconf.settings")" = '{}' ] \
  || fail "safe profile changes GNOME settings"

pass "Linux wiring, safety defaults, telemetry policy, shell, and JSON are valid"
