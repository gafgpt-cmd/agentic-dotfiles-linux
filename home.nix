{ config, pkgs, herdr-pkg, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  # Taken from the environment so no username or home path is ever committed.
  # Needs --impure (rebuild.sh and bootstrap.sh pass it); pure eval sees "".
  fromEnv = name:
    let v = builtins.getEnv name; in
    if v == "" then
      throw "$${name} is empty. Run ./rebuild.sh, or pass --impure to home-manager/nix."
    else v;
in

{
  imports = [ ./gnome.nix ];

  home.username = fromEnv "USER";
  home.homeDirectory = fromEnv "HOME";
  home.stateVersion = "24.11";
  home.packages = with pkgs; [
    # cli i use constantly
    ripgrep   # fast search
    fd        # fast find
    fzf       # fuzzy finder
    jq        # json on the command line
    lazygit
    mosh      # ssh that survives roaming/sleep; also provides mosh-server for inbound
    neovim
    # apps that were Homebrew casks/brews on macOS
    wezterm
    claude-code
    herdr-pkg
    # the font everything renders in
    nerd-fonts.hack
  ];
  fonts.fontconfig.enable = true;
  home.sessionVariables.EDITOR = "nvim";

  # Put the profiles on PATH ourselves instead of trusting the Nix installer's
  # shell hook. Determinate writes that hook to /etc/zshrc, which Debian's zsh
  # never reads (it uses /etc/zsh/zshrc), so an interactive shell ends up with a
  # bare /usr/bin PATH and none of the packages above.
  home.sessionPath = [
    "$HOME/.nix-profile/bin"          # everything in home.packages
    "/nix/var/nix/profiles/default/bin" # nix itself
  ];

  # Standalone home-manager doesn't ship its own CLI unless asked; rebuild.sh needs it.
  programs.home-manager.enable = true;

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
    initContent = ''
      bindkey '^f' autosuggest-accept
    '';
    shellAliases = {
      ".." = "cd ..";
      add = "git add .";
      push = "git push";
      pull = "git pull";
      m = "git switch main";
      cc = "claude --dangerously-skip-permissions";
      co = "codex --full-auto";
    };
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
      };
      cmd_duration.format = "[$duration]($style) ";
    };
  };

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/wezterm".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";
  home.file.".claude/statusline-command.sh".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/statusline-command.sh";

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
}
