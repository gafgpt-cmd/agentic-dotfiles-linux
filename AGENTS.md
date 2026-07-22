# Project notes for agents

Deliberate decisions in this repo - do NOT silently revert them:

- This is a Linux-only port of a macOS nix-darwin repo. Do not reintroduce nix-darwin, nix-homebrew, or `configuration.nix`. The macOS-to-Linux mapping is tabled at the end of README.md.
- Standalone home-manager is a deliberate choice over NixOS: the target machines run their own distro (Debian 13/GNOME today) and only the user environment is managed here. Anything needing root or a system service is out of scope.
- `herdr` is not in nixpkgs. It comes from its own upstream flake, pinned by tag in `flake.nix`. Bump the tag, do not vendor it.
- `bootstrap.sh` step 4 uses the distro's zsh, not the Nix one, on purpose: a broken home-manager generation must never remove the login shell of a remote machine. Do not "simplify" it to `~/.nix-profile/bin/zsh`.
- The flake is impure on purpose (`builtins.currentSystem`, `$USER`/`$HOME` via `getEnv`): nothing machine-specific may be committed. Do not "purify" it back to a hardcoded username or system; every nix/home-manager invocation must pass `--impure` (the scripts do).
- New packages go in `home.packages` in `home.nix`. Unfree ones need no extra work: `allowUnfree` is set on `pkgs` in `flake.nix`.
- Never commit `.no-mistakes/` validation evidence to this public repo. `.no-mistakes/` is gitignored; if a validation pipeline stages evidence into a branch, drop it before merging.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
