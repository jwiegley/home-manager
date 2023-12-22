{ config, lib, ... }:

with lib;

# Helper function to safely escape strings
let
  createQuadletSource = name: networkDef:
    let
      formatNetworkOption = k: v: "${k}=${v}";
      networkOptions = mapAttrsToList formatNetworkOption networkDef;
    in
    ''
      # Automatically generated by home-manager for podman network configuration
      # DO NOT EDIT THIS FILE DIRECTLY
      [Network]
      ${concatStringsSep "\n" networkOptions}

      [Install]
      WantedBy=multi-user.target default.target
    '';

  toQuadletInternal = name: networkDef:
    {
      serviceName = "podman-network-${name}";
      source = createQuadletSource name networkDef;
      unitType = "network";
    };

in
{
  options = {
    services.podman.networks = mkOption {
      type = types.attrsOf (types.attrsOf types.str);
      default = {};
      example = literalExample ''
        {
          mynetwork = {
            Subnet = "192.168.1.0/24";
            Gateway = "192.168.1.1";
            NetworkName = "mynetwork";
          };
        }
      '';
      description = "Defines Podman network quadlet configurations.";
    };
  };

  config = {
    internal.podman-quadlet-definitions = mapAttrsToList toQuadletInternal config.services.podman.networks;
  };
}
