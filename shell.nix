{ pkgs ? import <nixpkgs> { }, ... }:

pkgs.mkShell {
  packages = with pkgs; [
    git
    go_1_24
  ];
}
