{ config, lib, ... }:

let
  inherit (lib)
    mkRenamedOptionModule
    mkRemovedOptionModule
    mkEnableOption
    mkIf
    mkOption
    types
    lists
    ;
  cfg = config.services.tailscaleForwardAuth;
  cfgNginx = config.services.nginx.tailscaleForwardAuth;

  anyVirtualHostEnabled = lists.findFirst (v: v) false (lib.mapAttrsToList (_: host: host.tailscaleForwardAuth.enable) config.services.nginx.virtualHosts);

  virtualHostOptions = ({ config, ... }:
    let
      cfgHost = config.tailscaleForwardAuth;
    in
    {
      options.tailscaleForwardAuth = {
        enable = mkEnableOption "Enable Tailscale Forward Auth for this virtual host" // {
          default = cfgNginx.enable;
        };

        permitPrivate = mkEnableOption "Permit access from private IPs without Tailscale" // {
          default = cfgNginx.permitPrivate;
        };

        expectedTailnet = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "tailnet012345.ts.net";
          description = ''
            If you want to prevent node sharing from allowing users to access services
            across tailnets, declare your expected tailnets domain here.
            May be overridden in each virtual host.
          '';
        };

        requiresCapability = mkOption {
          type = types.nullOr types.str;
          default = cfgNginx.requiresCapability;
          description = "If set, the user must have this capability to access the virtual host";
        };
      };

      config = lib.mkIf cfgHost.enable {
        locations."/auth".extraConfig = ''  
          internal;

          proxy_pass http://unix:${cfg.socketPath};
          proxy_pass_request_body off;

          # Upstream uses $http_host here, but we are using gixy to check nginx configurations
          # gixy wants us to use $host: https://github.com/yandex/gixy/blob/master/docs/en/plugins/hostspoofing.md
          proxy_set_header Host $host;
          proxy_set_header Remote-Addr $remote_addr;
          proxy_set_header Remote-Port $remote_port;
          proxy_set_header Original-URI $request_uri;
          
          ${lib.optionalString ( cfgHost.permitPrivate != null ) 
            ''proxy_set_header Permit-Private "${if cfgHost.permitPrivate then "TRUE" else "FALSE"}";''
          }
          ${lib.optionalString ( cfgHost.expectedTailnet != null ) 
            ''proxy_set_header Expected-Tailnet "${cfgHost.expectedTailnet}";''
          }
          ${lib.optionalString ( cfgHost.requiresCapability != null ) 
            ''proxy_set_header Requires-Capability "${cfgHost.requiresCapability}";''
          }
        '';

        locations."/".extraConfig = ''
          auth_request /auth;
          auth_request_set $auth_user $upstream_http_tailscale_user;
          auth_request_set $auth_name $upstream_http_tailscale_name;
          auth_request_set $auth_login $upstream_http_tailscale_login;
          auth_request_set $auth_tailnet $upstream_http_tailscale_tailnet;
          auth_request_set $auth_profile_picture $upstream_http_tailscale_profile_picture;

          proxy_set_header X-Webauth-User "$auth_user";
          proxy_set_header X-Webauth-Name "$auth_name";
          proxy_set_header X-Webauth-Login "$auth_login";
          proxy_set_header X-Webauth-Tailnet "$auth_tailnet";
          proxy_set_header X-Webauth-Profile-Picture "$auth_profile_picture";
        '';
      };
    });
in
{
  # This module is intended to replace the nixpkgs module.
  disabledModules = [ "services/web-servers/nginx/tailscale-auth.nix" ];

  # imports = [
  #   (mkRenamedOptionModule [ "services" "nginx" "tailscaleAuth" ] [ "services" "nginx" "tailscaleForwardAuth" ])
  #   (mkRemovedOptionModule [ "services" "nginx" "tailscaleAuth" "virtualHosts" ] "use services.nginx.virtualHosts.<virtualHost>.enable instead")
  # ];

  options.services.nginx = {
    tailscaleForwardAuth = {
      enable = mkEnableOption "Enable Tailscale Forward Auth for all nginx virtual hosts";

      socketPath = mkOption {
        type = types.path;
        default = cfg.socketPath;
        description = ''
          Path of the socket listening to authorization requests.
        '';
      };

      permitPrivate = mkEnableOption "Permit access from private IPs without Tailscale";

      expectedTailnet = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "tailnet012345.ts.net";
        description = ''
          If you want to prevent node sharing from allowing users to access services
          across tailnets, declare your expected tailnets domain here.
          May be overridden in each virtual host.
        '';
      };

      requiresCapability = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "example.com/cap/access";
        description = ''
          The default capability required to access any virtual host.
          May be overridden in each virtual host.
        '';
      };
    };

    virtualHosts = mkOption {
      type = types.attrsOf (types.submodule virtualHostOptions);
    };
  };

  config = mkIf (cfgNginx.enable || anyVirtualHostEnabled) {
    services.tailscaleForwardAuth.enable = true; # not sure how I feel about this either.
    # services.nginx.enable = true; # I don't feel a submodule of nginx should enable nginx by default.

    users.users.${config.services.nginx.user}.extraGroups = [ cfg.group ];

    systemd.services.tailscale-forward-auth = {
      after = [ "nginx.service" ]; # is this the correct order?
      wants = [ "nginx.service" ];
    };
  };
}
