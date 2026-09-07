{
  config,
  lib,
  pkgs,
  ...
}:
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
    # The preserved Alpine image has FFmpeg but no Intel VA-API driver. Use the
    # host's pinned FFmpeg and driver closure, without modifying the image.
    virtualisation.oci-containers.containers.stash.volumes =
      lib.mkIf config.nixflixHost.gpuPassthrough.enable
        [
          "/nix/store:/nix/store:ro"
          "/run/opengl-driver:/run/opengl-driver:ro"
        ];
    virtualisation.oci-containers.containers.stash.environment =
      lib.mkIf config.nixflixHost.gpuPassthrough.enable
        {
          STASH_FFMPEG_PATH = "${pkgs.ffmpeg}/bin/ffmpeg";
          STASH_FFPROBE_PATH = "${pkgs.ffmpeg}/bin/ffprobe";
          LIBVA_DRIVER_NAME = "iHD";
          LIBVA_DRIVERS_PATH = "/run/opengl-driver/lib/dri";
        };
  };
}
