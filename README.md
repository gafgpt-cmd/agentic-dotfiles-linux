# dotfiles (Linux)

Linux port of [kunchenguid/dotfiles](https://github.com/kunchenguid/dotfiles), based on [GuillaumeTaffin/dotfiles-linux](https://github.com/GuillaumeTaffin/dotfiles-linux) and managed with standalone Home Manager.
One repo, one command, and a fresh Linux box ends up configured the same way every time.

Tested on Debian 13 with GNOME and Ubuntu 22.04/Linux Lite with XFCE. The distro-aware zsh installer supports apt, dnf, and pacman.

Nothing machine-specific is committed: username, home directory, and CPU architecture are read from the environment at switch time (hence `--impure` in the scripts). Clone it on any Linux box and run it as any user.

## What you get

Running the switch builds:

- Nix user packages (Git, GitHub CLI, ripgrep, fd, fzf, jq, lazygit, tmux, mise, uv, TypeScript, shellcheck, shfmt, Mosh, Neovim, WezTerm, Claude Code, Pi, herdr, Hack Nerd Font)
- Selectable XFCE, GNOME, KDE Plasma, or no desktop settings
- Shell (zsh, aliases, starship prompt)
- Editor (Neovim config with the rose-pine moon theme)
- Terminal (WezTerm with rose-pine moon and clear inactive-window dimming)
- Selective Pi resources: theme, terminal-title extension, Calm mode, model overrides, and pinned packages
- Telemetry and error-reporting opt-outs across the managed agent and developer tools

The committed profile is deliberately non-invasive: it installs the packages and privacy controls but adopts no existing app, shell, agent, or desktop configuration. Each config family has a separate opt-in switch in `profile.nix`.

## Prerequisites

- Linux (x86_64 or ARM; the architecture is detected at switch time).

## Fresh-machine setup

From a bare clone:

```sh
git clone https://github.com/gafgpt-cmd/agentic-dotfiles-linux.git
cd agentic-dotfiles-linux
```

Before you run it: review "Make it yours" below.

```sh
./bootstrap.sh
```

`bootstrap.sh` does five things, in order.
It is idempotent: re-running it on a configured machine is a no-op that ends in a green step 5.

1. Installs Determinate Nix, if it isn't already installed.
2. Symlinks this repo to `~/.dotfiles`.
   This has to happen before the first build, because `home.nix` points at config files through `~/.dotfiles`.
   If that path already exists and points elsewhere, bootstrap stops instead of replacing it.
3. Runs the first `home-manager switch`.
   It fetches the `home-manager` tool from the release-26.05 branch, then applies this repo's locked flake config for your user (read from the environment, nothing to edit).
   No sudo: standalone home-manager only writes inside your home directory.
4. If `manageShell` is enabled, installs zsh from the distro package manager and makes it your login shell.
   Deliberately the distro's zsh and not Nix's: `/usr/bin/zsh` always exists, so a broken home-manager generation can never lock you out of an SSH login.
   With the safe default, the existing login shell, `~/.zshrc`, `~/.zshenv`, and starship config remain untouched.
5. Verifies installed binaries plus only the files explicitly adopted in `profile.nix`, and exits non-zero listing whatever failed.
   Any earlier step that dies also prints a `BOOTSTRAP FAILED` banner, so a partial setup can't be mistaken for a finished one.

It asks for sudo only if Nix or the optional distro zsh package must be installed.

After that, `home-manager` exists and you're on the normal workflow below.

### Validate without applying

```sh
nix --extra-experimental-features 'nix-command flakes' flake check --no-build --impure
nix --extra-experimental-features 'nix-command flakes' build .#homeConfigurations.default.activationPackage --dry-run --impure
./tests/linux-config.test.sh
./tests/profile-matrix.test.sh
./tests/pi-calm.test.sh
./tests/build-matrix.sh
```

`--impure` is required: the flake reads `$USER`, `$HOME`, and the CPU architecture from the environment.

## Daily use

Edit the config files in place, then apply:

```sh
./rebuild.sh
```

### Connecting with Mosh

The switch installs `mosh-server`, so from any machine with a mosh client:

```sh
mosh <host>
```

Two things must hold:

- If `manageShell` is enabled, bootstrap sets zsh as the login shell and Home Manager puts `~/.nix-profile/bin` on its non-interactive PATH.
- You must allow Mosh's UDP ports through your firewall. The default range is 60000-61000; a smaller explicit range works with `mosh -p 60000:60010 <host>`.

If the client reports `mosh-server: command not found`, bypass PATH: `mosh --server='.nix-profile/bin/mosh-server' <host>`.

## Make it yours

Username, home directory, and CPU architecture need no editing: they come from the environment at switch time.

The checked-in `profile.nix` is safe for an established machine: `desktop = "none"` and every adoption switch is false. Enable only the parts you want Home Manager to own:

- `desktop`: `xfce`, `gnome`, `kde`, or `none`.
- `displayServer`: `x11`, `wayland`, or `auto`. Explicit values select WezTerm's native backend; `auto` leaves toolkit detection alone.
- `manageShell`: zsh files, aliases, editor variable, starship config, and login-shell setup.
- `manageNvim`, `manageWezterm`, `manageHerdr`: the matching config directory.
- `managePiResources`: Pi settings, model overrides, themes, and extensions; never credentials, sessions, caches, or runtime state.
- `manageClaudeSettings`: off by default so an established Claude setup is not replaced.
- `manageAgentInstructions`: off by default so Kun's policy does not silently replace your own Claude, Codex, or OpenCode instructions.

**Git identity:** this config deliberately does not set your git name or email.
Git will stop your first commit and tell you to set them (`git config --global user.name "Your Name"` and `git config --global user.email you@example.com`).
If you'd rather manage that declaratively, add this to `home.nix` with your own identity:

```nix
programs.git = {
  enable = true;
  settings.user = {
    name = "Your Name";
    email = "you@example.com";
  };
};
```

The `cc` and `co` aliases launch Claude and Codex with their normal configured permission behavior. This fork does not force bypass or full-auto modes.

## Repo tour

- `flake.nix` - the entry point.
  Wires up nixpkgs, home-manager, and the herdr flake, and declares the `homeConfigurations` output.
- `profile.nix` - desktop choice and adoption switches for existing agent configuration.
- `home.nix` - user-level config: shell, packages, prompt, and the symlinks described below.
- `gnome.nix` / `xfce.nix` / `kde.nix` - optional Linux desktop mappings for macOS defaults.
- `rebuild.sh` - re-applies the config after the first switch.
- `home/` - edit-in-place app and agent resources.
- `tests/` - Linux wiring, full desktop/session matrix, and Pi Calm behavior tests.

## How the symlinks work

For a config family enabled in `profile.nix`, the files under `home/` become the live files; editing them needs no rebuild.
`home.nix` uses `mkOutOfStoreSymlink` to point adopted paths like `~/.config/nvim` straight at this repo, so the two never drift out of sync. Disabled families are not touched.
You only run `./rebuild.sh` when you change something that isn't just a symlinked file, like a package list or a dconf setting.

Pi is handled more narrowly: Home Manager links authored themes, extensions, `models.json`, and `settings.json`, never `~/.pi/agent` as a whole. Credentials, sessions, caches, downloaded packages, and Calm's local toggle remain outside Git.

The Pi settings pin `pi-web-access`, Codex fast mode, and OpenAI server-side compaction. These packages execute with your user permissions; review their immutable versions in `home/.pi/agent/settings.json` before switching. The compaction package sends relevant conversation state to OpenAI.
Pi itself is pinned through a separate nixpkgs snapshot because the 26.05 stable snapshot still carries Pi 0.75; the Calm extension's real terminal test targets the pinned Pi 0.84.

## Desktop and display-server support

The flake exposes and builds six profiles: GNOME, XFCE, and KDE Plasma on both X11 and Wayland. Desktop modules only configure user preferences; the distro remains responsible for installing the desktop, display manager, GPU stack, and session itself.

| Profile | Settings backend | X11 | Wayland |
| --- | --- | --- | --- |
| GNOME | Home Manager dconf | Build-tested | Build-tested |
| XFCE | Home Manager GTK/xfconf | Build-tested | Build-tested portable subset; [XFCE's Wayland session remains preliminary](https://wiki.xfce.org/releng/wayland_roadmap) |
| KDE Plasma | Plasma Manager, non-destructive mode | Build-tested | Build-tested |

`displayServer = "x11"` makes an adopted WezTerm config use X11. `displayServer = "wayland"` enables its [native Wayland backend](https://wezterm.org/config/lua/config/enable_wayland.html). `auto` keeps WezTerm's own detection. GNOME dconf and KDE Plasma preferences are shared by both session types. XFCE's Wayland profile omits X11-only XSettings and xfwm4 keys while retaining GTK, Thunar, and xfdesktop preferences.

## Telemetry policy

Telemetry is off across the managed stack. Home Manager exports the supported Claude Code, Pi, OpenTelemetry, GNHF, no-mistakes, Lavish AXI, Homebrew, JavaScript framework, .NET, PowerShell, HashiCorp, Scarf, Hugging Face, and DVC opt-out variables. Pi's settings also explicitly disable its install ping and opt-in analytics; its separate version check is disabled too.

Codex needs an additional config change because its analytics setting defaults to enabled independently of generic OpenTelemetry variables. Each switch atomically preserves the rest of `~/.codex/config.toml` while enforcing:

```toml
[analytics]
enabled = false

[otel]
exporter = "none"
trace_exporter = "none"
metrics_exporter = "none"
log_user_prompt = false
```

The bundled local extensions and pinned Pi packages were checked for additional remote analytics hooks. Functional network traffic remains: model/API calls, web access, GitHub access, package downloads, and the explicitly documented server-side compaction request are not telemetry.

## What changed from the macOS original

| macOS | Linux |
| --- | --- |
| nix-darwin `darwinConfigurations` | standalone home-manager `homeConfigurations` |
| `configuration.nix` system defaults | selected `gnome.nix`, `xfce.nix`, `kde.nix`, or none |
| Homebrew casks (`wezterm`, `claude-code`) | nixpkgs packages in `home.nix` |
| `herdr` Homebrew formula | the upstream herdr flake, pinned in `flake.nix` |
| `darwin-rebuild switch` (sudo) | `home-manager switch` (no sudo) |
| `/Users/$user` | `/home/$user` |

Dropped with no portable Linux equivalent: menu-bar behavior, hardware-specific touchpad settings, and WezTerm's `macos_window_background_blur`. Window blur remains the compositor's job.

## License

MIT No Attribution. See `LICENSE`.
