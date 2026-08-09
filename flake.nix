{
  description = "dotfiles (Linux)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # The stable 26.05 snapshot still has Pi 0.75. Calm is proved against 0.84.
    nixpkgs-pi.url = "github:NixOS/nixpkgs/nixos-unstable";

    # herdr isn't in nixpkgs; upstream ships its own flake, Linux included.
    herdr.url = "github:ogulcancelik/herdr/v0.7.4";
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-pi, home-manager, herdr }:
    let
      # Impure on purpose: the same clone must work on any machine, any user,
      # any CPU arch, with nothing machine-specific committed here. The scripts
      # pass --impure; without it currentSystem (and $USER/$HOME in home.nix)
      # are unavailable and evaluation fails with a clear error.
      system = builtins.currentSystem;
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true; # claude-code
      };
      pi-pkg = nixpkgs-pi.legacyPackages.${system}.pi-coding-agent;
      profile = import ./profile.nix;
      codexPrivacy = pkgs.writeShellApplication {
        name = "ensure-codex-privacy";
        runtimeInputs = [ (pkgs.python3.withPackages (ps: [ ps.tomlkit ])) ];
        text = ''
          exec python ${./scripts/ensure-codex-privacy.py} "$@"
        '';
      };
    in
    {
      homeConfigurations.default = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          herdr-pkg = herdr.packages.${system}.default;
          inherit codexPrivacy pi-pkg profile;
        };
        modules = [ ./home.nix ];
      };

      packages.${system} = {
        ensure-codex-privacy = codexPrivacy;
        pi = pi-pkg;
      };
    };
}
