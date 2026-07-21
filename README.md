# dotfiles (Linux)

Linux port of [kunchenguid/dotfiles](https://github.com/kunchenguid/dotfiles), managed with standalone home-manager.
One repo, one command, and a fresh Linux box ends up configured the same way every time.

Tested on Debian 13 (trixie) with GNOME. Any systemd distro should work: the only distro-aware code is the zsh install in `bootstrap.sh` step 5 (apt, dnf, pacman).

## What you get

Running the switch builds:

- Nix user packages (ripgrep, fd, fzf, jq, lazygit, Neovim, WezTerm, Claude Code, herdr, Hack Nerd Font)
- GNOME settings via dconf (dark theme, fast key repeat, tap to click, Nautilus list view)
- Shell (zsh, aliases, starship prompt)
- Editor (Neovim config with the rose-pine moon theme)
- Terminal (WezTerm config with the rose-pine moon theme)
- Agent configs (Claude, Codex, opencode all share one AGENTS.md)

## Prerequisites

- x86_64 Linux, by default.
- ARM: set `system = "aarch64-linux";` in `flake.nix` (the comment right there tells you the same thing).

## Fresh-machine setup

From a bare clone:

```sh
git clone <this repo>
cd dotfiles-linux
```

Before you run it: review "Make it yours" below.

```sh
./bootstrap.sh
```

`bootstrap.sh` does five things, in order:

1. Installs Determinate Nix, if it isn't already installed.
2. Symlinks this repo to `~/.dotfiles`.
   This has to happen before the first build, because `home.nix` points at config files through `~/.dotfiles`.
3. Checks the `user` configured in `flake.nix` against your actual username, and offers to fix it for you if they differ.
4. Runs the first `home-manager switch`.
   It fetches the `home-manager` tool from the release-26.05 branch, then applies this repo's locked flake config.
   No sudo: standalone home-manager only writes inside your home directory.
5. Installs zsh from the distro package manager and makes it your login shell.
   Deliberately the distro's zsh and not Nix's: `/usr/bin/zsh` always exists, so a broken home-manager generation can never lock you out of an SSH login.
   `~/.zshrc` itself is fully managed by home-manager either way.

It asks for your sudo password (steps 1 and 5). Nothing else is manual: log out, log back in, and the machine is done.

After that, `home-manager` exists and you're on the normal workflow below.

### Validate without applying

```sh
nix flake check --no-build
nix build .#homeConfigurations.mega01.activationPackage --dry-run
```

Substitute your username for `mega01`.

## Daily use

Edit the config files in place, then apply:

```sh
./rebuild.sh
```

## Make it yours

- **Username**: run `./bootstrap.sh` (it detects your username and offers to set it) OR change the single `user = "mega01"` line in `flake.nix`.
  Everything else (`home.nix`, home directory paths, the flake output name) is threaded from that one variable.
- **CPU architecture**: `system` in `flake.nix`.

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

**Heads-up:**

- `home/AGENTS.md` is a personal agent policy, and `home.nix` installs it for Claude, Codex, and opencode.
- The `cc` and `co` shell aliases in `home.nix` are high-agency shortcuts: `claude --dangerously-skip-permissions` and `codex --full-auto`.
  Know what they do before you use them.

## Repo tour

- `flake.nix` - the entry point.
  Wires up nixpkgs, home-manager, and the herdr flake, and declares the `homeConfigurations` output.
- `home.nix` - user-level config: shell, packages, prompt, and the symlinks described below.
- `gnome.nix` - desktop settings via dconf. This is what replaced macOS `system.defaults`.
- `rebuild.sh` - re-applies the config after the first switch.
- `home/` - the actual config files that get symlinked into place (Neovim, WezTerm, herdr, Claude settings, the shared `AGENTS.md`).

## How the symlinks work

The files under `home/` are the real files - editing them here is editing your live config, no rebuild needed to see the change in your editor.
`home.nix` uses `mkOutOfStoreSymlink` to point paths like `~/.config/nvim` straight at `home/.config/nvim` in this repo, so the two never drift out of sync.
You only run `./rebuild.sh` when you change something that isn't just a symlinked file, like a package list or a dconf setting.

## What changed from the macOS original

| macOS | Linux |
| --- | --- |
| nix-darwin `darwinConfigurations` | standalone home-manager `homeConfigurations` |
| `configuration.nix` system defaults | `gnome.nix` dconf settings |
| Homebrew casks (`wezterm`, `claude-code`) | nixpkgs packages in `home.nix` |
| `herdr` Homebrew formula | the upstream herdr flake, pinned in `flake.nix` |
| `darwin-rebuild switch` (sudo) | `home-manager switch` (no sudo) |
| `/Users/$user` | `/home/$user` |

Dropped with no Linux equivalent: menu-bar auto-hide, dock auto-hide (stock GNOME has no persistent dock), "show all file extensions" (Nautilus always does), and WezTerm's `macos_window_background_blur`.

## License

MIT No Attribution. See `LICENSE`.
