{ config
, lib
, pkgs
, ...
}:

let
  inherit (lib)
    getExe
    mkEnableOption
    mkPackageOption
    mkRenamedOptionModule
    mkIf
    mkOption
    types
    ;
  cfg = config.services.tailscaleForwardAuth;
in
{

  disabledModules = [ "services/networking/tailscale-auth.nix" ];
  #
  # imports = [
  #   (mkRenamedOptionModule [ "services" "tailscaleAuth" ] [ "services" "tailscaleForwardAuth" ])
  # ];

  options.services.tailscaleForwardAuth = {
    enable = mkEnableOption "tailscale-forward-auth, to authenticate users via tailscale";

    package = mkPackageOption pkgs "tailscale-forward-auth" { };

    user = mkOption {
      type = types.str;
      default = "tailscale-forward-auth";
      description = "User which runs tailscale-forward-auth";
    };

    group = mkOption {
      type = types.str;
      default = "tailscale-forward-auth";
      description = "Group which runs tailscale-forward-auth";
    };

    socketPath = mkOption {
      default = "/run/tailscale-forward-auth/tailscale-forward-auth.sock";
      type = types.path;
      description = ''
        Path of the socket listening to authorization requests.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.tailscale.enable = true;

    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
    };
    users.groups.${cfg.group} = { };

    systemd.sockets.tailscale-forward-auth = {
      description = "Tailscale Forward Authentication socket";
      partOf = [ "tailscale-forward-auth.service" ];
      wantedBy = [ "sockets.target" ];
      listenStreams = [ cfg.socketPath ];
      socketConfig = {
        SocketMode = "0660";
        SocketUser = cfg.user;
        SocketGroup = cfg.group;
      };
    };

    systemd.services.tailscale-forward-auth = {
      description = "Tailscale Forward Authentication service";
      requires = [ "tailscale-forward-auth.socket" ];

      serviceConfig = {
        ExecStart = getExe cfg.package;
        RuntimeDirectory = "tailscale-forward-auth";
        User = cfg.user;
        Group = cfg.group;

        BindPaths = [ "/run/tailscale/tailscaled.sock" ];

        CapabilityBoundingSet = "";
        DeviceAllow = "";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        PrivateDevices = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        RestrictNamespaces = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        RestrictRealtime = true;
        RestrictSUIDSGID = true;

        SystemCallArchitectures = "native";
        SystemCallErrorNumber = "EPERM";
        SystemCallFilter = [
          "@system-service"
          "~@cpu-emulation"
          "~@debug"
          "~@keyring"
          "~@memlock"
          "~@obsolete"
          "~@privileged"
          "~@setuid"
        ];
      };
    };
  };
}
