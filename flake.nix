{
  description = "dev shell for nix people";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, flake-utils, nixpkgs, ... }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import nixpkgs { inherit system; };

          inherit (pkgs) callPackage;
        in
        {
          packages.default = callPackage ./default.nix { };
          devShells.default = callPackage ./shell.nix { };

        }) // {

      overlays.default = final: prev: {
        tailscale-forward-auth = self.packages.${final.system}.default;

      };
      nixosModules.default = import ./nixos/modules;
    };
}
