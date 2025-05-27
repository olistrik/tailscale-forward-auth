{ ... }: {
  imports = [
    ./tailscale-forward-auth.nix
    ./nginx.nix
  ];
}
