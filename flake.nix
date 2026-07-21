{
  description = "dotfiles (Linux)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # herdr isn't in nixpkgs; upstream ships its own flake, Linux included.
    herdr.url = "github:ogulcancelik/herdr/v0.7.4";
  };

  outputs = inputs@{ self, nixpkgs, home-manager, herdr }:
    let
      # The one username line to change if this isn't your machine.
      # bootstrap.sh offers to rewrite this for you if your Linux username differs.
      user = "mega01";
      # Use "aarch64-linux" on ARM machines.
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true; # claude-code
      };
    in
    {
      homeConfigurations.${user} = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          inherit user;
          herdr-pkg = herdr.packages.${system}.default;
        };
        modules = [ ./home.nix ];
      };
    };
}
