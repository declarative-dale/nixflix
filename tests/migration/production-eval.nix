{ pkgs, host }:
let
  cfg = host.config;
  native = [
    "sonarr"
    "sonarr-4k"
    "radarr"
    "radarr-4k"
    "prowlarr"
    "sabnzbd"
    "plex"
    "seerr"
    "lidarr"
    "bazarr"
    "bazarr-4k"
    "tautulli"
    "audiobookshelf"
    "readarr"
    "whisparr"
  ];
in
assert cfg.nixflixHost.production.enable;
assert builtins.elem "rw" cfg.fileSystems."/data".options;
assert cfg.networking.firewall.allowedTCPPorts == [ 22 ];
assert cfg.virtualisation.oci-containers.backend == "podman";
assert cfg.virtualisation.oci-containers.containers.apprise.ports == [ "127.0.0.1:8000:8000" ];
assert builtins.all (
  name: !(cfg.systemd.services.${name}.serviceConfig ? NetworkNamespacePath)
) native;
assert builtins.all (name: builtins.elem "data.mount" cfg.systemd.services.${name}.bindsTo) native;
assert builtins.all (
  name:
  cfg.systemd.services.${name}.unitConfig.ConditionPathExists
  == "/var/lib/nixflix-migration/ready/${name}"
) native;
assert
  builtins.attrNames cfg.virtualisation.oci-containers.containers == [
    "apprise"
    "mylar3"
    "stash"
  ];
pkgs.runCommand "production-eval" { } "touch $out"
