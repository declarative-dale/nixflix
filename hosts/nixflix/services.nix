{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  secret = name: { _secret = "/var/lib/nixflix-secrets/current/${name}"; };
  arr = name: port: {
    enable = true;
    config.apiKey = secret name;
    config.hostConfig = {
      inherit port;
      bindAddress = "127.0.0.1";
      username = null;
    };
    # Preserve restored root folders; do not run automatic deletion/reconciliation.
    mediaDirs = [ ];
    config.rootFolders = lib.mkForce [ ];
  };
  images = builtins.fromJSON (builtins.readFile ./containers.json);
  containers = {
    bazarr = {
      port = 6767;
      internal = 6767;
    };
    bazarr-4k = {
      port = 6777;
      internal = 6767;
    };
    whisparr = {
      port = 6969;
      internal = 6969;
    };
    readarr = {
      port = 8787;
      internal = 8787;
    };
    mylar3 = {
      port = 8090;
      internal = 8090;
    };
    notifiarr = {
      port = 5454;
      internal = 5454;
    };
    tautulli = {
      port = 8181;
      internal = 8181;
    };
    audiobookshelf = {
      port = 13378;
      internal = 80;
    };
    stash = {
      port = 9999;
      internal = 9999;
    };
  };
in
{
  nixflix = {
    enable = true;
    mediaDir = "/data/media";
    downloadsDir = "/data/usenet";
    serviceDependencies = [ "nixflix-nas-ready.service" ];
    sonarr = arr "sonarr" 8990;
    sonarr-4k = arr "sonarr-4k" 8989;
    radarr = arr "radarr" 7879;
    radarr-4k = arr "radarr-4k" 7878;
    lidarr = arr "lidarr" 8686;
    prowlarr = {
      enable = true;
      config.apiKey = secret "prowlarr";
      config.hostConfig = {
        bindAddress = "127.0.0.1";
        username = null;
      };
    };
    usenetClients.sabnzbd = {
      enable = true;
      downloadsDir = "/data/usenet";
      settings.misc = {
        api_key = secret "sabnzbd";
        nzb_key = secret "sabnzbd";
        host = "127.0.0.1";
        port = 8080;
      };
    };
    recyclarr = {
      enable = true;
      cleanupUnmanagedProfiles.enable = false;
      config = {
        sonarr.sonarr.media_naming = lib.mkForce null;
        sonarr.sonarr-4k.media_naming = lib.mkForce null;
        radarr.radarr.media_naming = lib.mkForce null;
        radarr.radarr-4k.media_naming = lib.mkForce null;
      };
    };
    # Leave source download client state intact until explicitly reconciled.
    downloadarr.enable = false;
  };
  environment.etc."nixflix/recyclarr-settings.yml".source =
    (pkgs.formats.yaml { }).generate "recyclarr-settings.yml"
      {
        resource_providers = [
          {
            name = "pinned-guides";
            type = "trash-guides";
            path = "${inputs.trash-guides}";
            replace_default = true;
          }
          {
            name = "pinned-templates";
            type = "config-templates";
            path = "${inputs.recyclarr-templates}";
            replace_default = true;
          }
        ];
      };
  systemd.services.recyclarr = {
    after = lib.mkForce [
      "nixflix-staging-network.service"
      "sonarr.service"
      "sonarr-4k.service"
      "radarr.service"
      "radarr-4k.service"
    ];
    requires = lib.mkForce [
      "nixflix-staging-network.service"
      "sonarr.service"
      "sonarr-4k.service"
      "radarr.service"
      "radarr-4k.service"
    ];
    preStart = lib.mkBefore "cp /etc/nixflix/recyclarr-settings.yml /var/lib/recyclarr/settings.yml";
  };
  services.plex = {
    enable = true;
    group = "media";
    dataDir = "/var/lib/plex";
  };
  users.users.plex.extraGroups = [
    "video"
    "render"
  ];
  systemd.services.plex.serviceConfig.BindReadOnlyPaths = [ "/data/media:/media" ];
  services.seerr = {
    enable = true;
    port = 5055;
  };
  users.users.seerr = {
    isSystemUser = true;
    group = "media";
  };
  systemd.services.seerr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "seerr";
    Group = "media";
  };
  # Keep SABnzbd's copied provider, path and queue settings. Update only the bind address.
  systemd.services.sabnzbd.serviceConfig.ExecStartPre = lib.mkForce (
    "+"
    + pkgs.writeShellScript "sabnzbd-migration-prestart" ''
      set -eu
      test -f /var/lib/sabnzbd/sabnzbd.ini
      ${pkgs.python3.withPackages (p: [ p.configobj ])}/bin/python3 - <<'PY'
      from configobj import ConfigObj
      c = ConfigObj('/var/lib/sabnzbd/sabnzbd.ini')
      c['misc']['host'] = '127.0.0.1'
      c['misc']['port'] = '8080'
      c['misc']['api_key'] = open('/var/lib/nixflix-secrets/current/sabnzbd').read().strip()
      c.write()
      PY
      chown sabnzbd:media /var/lib/sabnzbd/sabnzbd.ini
      chmod 600 /var/lib/sabnzbd/sabnzbd.ini
    ''
  );
  virtualisation.podman.enable = true;
  virtualisation.oci-containers = {
    backend = "podman";
    containers = lib.mapAttrs (name: _c: {
      image = images.${name};
      autoStart = false;
      environment = {
        PUID = "1100";
        PGID = "169";
        TZ = "America/Chicago";
      }
      // lib.optionalAttrs (name == "audiobookshelf") { PORT = "13378"; };
      volumes =
        if name == "stash" then
          [
            "/var/lib/nixflix-containers/stash/config:/root/.stash"
            "/var/lib/nixflix-containers/stash/generated:/generated"
            "/var/lib/nixflix-containers/stash/metadata:/metadata"
            "/var/lib/nixflix-containers/stash/cache:/cache"
            "/data/media/porn:/data:ro"
          ]
        else
          [
            "/var/lib/nixflix-containers/${name}:/config"
            "/data:/data:ro"
          ]
          ++ lib.optionals (name == "audiobookshelf") [
            "/var/lib/nixflix-containers/audiobookshelf-metadata:/metadata"
            "/data/media/audiobooks:/audiobooks:ro"
            "/data/media/ebooks:/ebooks:ro"
            "/data/media/podcasts:/podcasts:ro"
          ];
      extraOptions = [ "--network=ns:/run/netns/nixflix-staging" ];
    }) containers;
  };
  users.users.media-container = {
    isSystemUser = true;
    uid = 1100;
    group = "media";
  };
  systemd.tmpfiles.rules = [ "d /var/lib/nixflix-containers 0700 root root -" ];
}
