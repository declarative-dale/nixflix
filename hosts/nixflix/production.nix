{ config, lib, ... }:
let
  cfg = config.nixflixHost.production;
  lanNetworks = [
    "10.69.0.0/24"
    "10.42.0.0/24"
  ];
  ports = [
    80
    5055
    6767
    6777
    6969
    7878
    7879
    8080
    8090
    8181
    8686
    8787
    8989
    8990
    9696
    9999
    13378
    32400
  ];
in
{
  options.nixflixHost.production.enable = lib.mkEnableOption "production media networking and NAS writes after cold cutover";
  config = lib.mkIf cfg.enable {
    # Keep globally routed IPv6 closed; the initial service audience is the LAN.
    networking.firewall.allowedTCPPorts = lib.mkForce [ 22 ];
    networking.firewall.extraCommands = lib.concatMapStringsSep "\n" (
      network:
      lib.concatMapStringsSep "\n" (
        port: "iptables -A nixos-fw -s ${network} -p tcp --dport ${toString port} -j nixos-fw-accept"
      ) ports
    ) lanNetworks;
    environment.etc."nixflix/mode".text = "production\n";
  };
}
