{ config, lib, ... }:
let
  proxy = import ../../lib/mkVirtualHosts.nix { inherit config lib; };
  # Existing request hostname is preserved. These additional names are local
  # routes only until LAN DNS / existing tunnel upstreams are changed at cutover.
  routes = {
    seeme = 5055;
    bazarr = 6767;
    bazarr-4k = 6777;
    whisparr = 6969;
    readarr = 8787;
    mylar3 = 8090;
    tautulli = 8181;
    audiobookshelf = 13378;
    stash = 9999;
  };
in
lib.mkMerge (
  [
    {
      nixflix.caddy = {
        enable = true;
        domain = "dalebox.pw";
        # The existing tunnel terminates HTTPS. No ACME traffic from staged clones.
        tls.enable = false;
      };
      systemd.services.caddy = lib.mkIf (!config.nixflixHost.production.enable) {
        requires = [ "nixflix-staging-network.service" ];
        after = [ "nixflix-staging-network.service" ];
        serviceConfig.NetworkNamespacePath = "/run/netns/nixflix-staging";
      };
    }
  ]
  ++ lib.mapAttrsToList (
    name: port:
    proxy.mkVirtualHost {
      hostname = "${name}.dalebox.pw";
      expose = true;
      inherit port;
      websocketUpgrade = true;
    }
  ) routes
)
