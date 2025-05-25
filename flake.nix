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
      in
      {
        packages.default = pkgs.buildGo124Module {
          pname = "tailscale-forward-auth";
          version = "0.0.0";
          src = ./.;
          vendorHash = "sha256-/MZJ73XS7s035LHUPhcIOjxLcM9OZDFO4wJD+NKQzJk=";
          excludedPackages = [ "example" ];
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            git
            go_1_24
          ];
        };
      });
}
