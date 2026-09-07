{ config, lib, ... }:
{
  options.nixflixHost.gpuPassthrough.enable = lib.mkEnableOption "Intel GPU access after hypervisor passthrough is configured";
  config = {
    services.plex.accelerationDevices =
      if config.nixflixHost.gpuPassthrough.enable then [ "/dev/dri/renderD128" ] else [ ];
    virtualisation.oci-containers.containers.stash.extraOptions =
      lib.mkIf config.nixflixHost.gpuPassthrough.enable
        [
          "--device=/dev/dri:/dev/dri"
          "--group-add=${toString config.users.groups.render.gid}"
          "--group-add=${toString config.users.groups.video.gid}"
        ];
  };
}
