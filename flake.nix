{
  description = "dev shell for nix people";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { flake-utils, nixpkgs, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        inherit (pkgs) callPackage;
      in
      rec {
        packages.default = callPackage ./default.nix { };
        devShells.default = callPackage ./shell.nix { };
        # nixosModules.default = import ./nix/module.nix;

        overlays.default = final: prev: {
          tailscale-nginx-auth = packages.default;
        };
      });
}
