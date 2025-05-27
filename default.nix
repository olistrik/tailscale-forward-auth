{ pkgs ? import <nixpkgs> { }, ... }:

pkgs.buildGo124Module {
  pname = "tailscale-forward-auth";
  version = "0.0.0";
  src = ./.;
  vendorHash = "sha256-xbR/vQ0BX0/ujJVuIcXNLAf/myiCZjGFe8sd2meaRGs=";
  excludedPackages = [ "example" ];

  meta = {
    mainProgram = "tailscale-forward-auth";
  };
}
