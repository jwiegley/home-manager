{ config, lib, pkgs, ... }:
let
  cfg = config.virtualisation.containers;

  inherit (lib) mkOption types;

  toml = pkgs.formats.toml { };
in {
  meta.maintainers = [ lib.maintainers.bad ];
  options.virtualisation.containers = {

    enable = lib.mkEnableOption "the common containers configuration module";

    ociSeccompBpfHook.enable = lib.mkEnableOption "the OCI seccomp BPF hook";

    containersConf.settings = mkOption {
      type = toml.type;
      default = { };
      description = "containers.conf configuration";
    };

    containersConf.cniPlugins = mkOption {
      type = types.listOf types.package;
      defaultText = ''
        [
          pkgs.cni-plugins
        ]
      '';
      example = lib.literalExample ''
        [
          pkgs.cniPlugins.dnsname
        ]
      '';
      description = ''
        CNI plugins to install on the system.
      '';
    };

    registries = {
      search = mkOption {
        type = types.listOf types.str;
        default = [ "docker.io" "quay.io" ];
        description = ''
          List of repositories to search.
        '';
      };

      insecure = mkOption {
        default = [ ];
        type = types.listOf types.str;
        description = ''
          List of insecure repositories.
        '';
      };

      block = mkOption {
        default = [ ];
        type = types.listOf types.str;
        description = ''
          List of blocked repositories.
        '';
      };
    };

    policy = mkOption {
      default = { };
      type = types.attrs;
      example = lib.literalExample ''
        {
          default = [ { type = "insecureAcceptAnything"; } ];
          transports = {
            docker-daemon = {
              "" = [ { type = "insecureAcceptAnything"; } ];
            };
          };
        }
      '';
      description = ''
        Signature verification policy file.
        If this option is empty the default policy file from
        <literal>skopeo</literal> will be used.
      '';
    };

  };

  config = lib.mkIf cfg.enable {
      assertions = [ {
        # It may be possible to make a similar module for macos but I don't have a mac device to try
        assertion = enabled -> pkgs.stdenv.isLinux;
        message = "Containers module only works on linux"
      }

    virtualisation.containers.containersConf.cniPlugins = [ pkgs.cni-plugins ];

    virtualisation.containers.containersConf.settings = {
      network.cni_plugin_dirs =
        map (p: "${lib.getBin p}/bin") cfg.containersConf.cniPlugins;
      engine = {
        init_path = "${pkgs.catatonit}/bin/catatonit";
      } // lib.optionalAttrs cfg.ociSeccompBpfHook.enable {
        hooks_dir = [ config.boot.kernelPackages.oci-seccomp-bpf-hook ];
      };
    };

    xdg.configFile."containers/containers.conf".source =
      toml.generate "containers.conf" cfg.containersConf.settings;

    xdg.configFile."containers/registries.conf".source =
      toml.generate "registries.conf" {
        registries = lib.mapAttrs (n: v: { registries = v; }) cfg.registries;
      };

    xdg.configFile."containers/policy.json".source = if cfg.policy != { } then
      pkgs.writeText "policy.json" (builtins.toJSON cfg.policy)
    else
      "${pkgs.skopeo.src}/default-policy.json";
  };

}
