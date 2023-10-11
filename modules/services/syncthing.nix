{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.services.syncthing;

  defaultSyncthingArgs = [
    "${pkgs.syncthing}/bin/syncthing"
    "-no-browser"
    "-no-restart"
    "-logflags=0"
  ];

  syncthingArgs = defaultSyncthingArgs ++ cfg.extraOptions;

in {
  meta.maintainers = [ maintainers.rycee ];

  options = {
    services.syncthing = {
      enable = mkEnableOption "Syncthing continuous file synchronization";

      extraOptions = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "--gui-apikey=apiKey" ];
        description = ''
          Extra command-line arguments to pass to {command}`syncthing`.
        '';
      };

      tray = mkOption {
        type = with types;
          either bool (submodule {
            options = {
              enable = mkOption {
                type = types.bool;
                default = false;
                description = "Whether to enable a syncthing tray service.";
              };

              command = mkOption {
                type = types.str;
                default = "syncthingtray";
                defaultText = literalExpression "syncthingtray";
                example = literalExpression "qsyncthingtray";
                description = "Syncthing tray command to use.";
              };

              extraOptions = mkOption {
                type = types.listOf types.str;
                default = [ ];
                example = [ "--wait" ];
                description = ''
                  Extra command-line arguments to pass to {command}`syncthingtray`.
                '';
              };

              package = mkOption {
                type = types.package;
                default = pkgs.syncthingtray-minimal;
                defaultText = literalExpression "pkgs.syncthingtray-minimal";
                example = literalExpression "pkgs.qsyncthingtray";
                description = "Syncthing tray package to use.";
              };
            };
          });
        default = { enable = false; };
        description = "Syncthing tray service configuration.";
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      home.packages = [ (getOutput "man" pkgs.syncthing) ];

      systemd.user.services = {
        syncthing = {
          Unit = {
            Description =
              "Syncthing - Open Source Continuous File Synchronization";
            Documentation = "man:syncthing(1)";
            After = [ "network.target" ];
          };

          Service = {
            ExecStart = escapeShellArgs syncthingArgs;
            Restart = "on-failure";
            SuccessExitStatus = [ 3 4 ];
            RestartForceExitStatus = [ 3 4 ];

            # Sandboxing.
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
            NoNewPrivileges = true;
            PrivateUsers = true;
            RestrictNamespaces = true;
            SystemCallArchitectures = "native";
            SystemCallFilter = "@system-service";
          };

          Install = { WantedBy = [ "default.target" ]; };
        };
      };

      launchd.agents.syncthing = {
        enable = true;
        config = {
          ProgramArguments = syncthingArgs;
          KeepAlive = {
            Crashed = true;
            SuccessfulExit = false;
          };
          ProcessType = "Background";
        };
      };
    })

    (mkIf (isAttrs cfg.tray && cfg.tray.enable) {
      assertions = [
        (hm.assertions.assertPlatform "services.syncthing.tray" pkgs
          platforms.linux)
      ];

      systemd.user.services = {
        ${cfg.tray.package.pname} = {
          Unit = {
            Description = cfg.tray.package.pname;
            Requires = [ "tray.target" ];
            After = [ "graphical-session-pre.target" "tray.target" ];
            PartOf = [ "graphical-session.target" ];
          };

          Service = {
            ExecStart = escapeShellArgs
              ([ "${cfg.tray.package}/bin/${cfg.tray.command}" ]
                ++ cfg.tray.extraOptions);
          };

          Install = { WantedBy = [ "graphical-session.target" ]; };
        };
      };
    })

    # deprecated
    (mkIf (isBool cfg.tray && cfg.tray) {
      assertions = [
        (hm.assertions.assertPlatform "services.syncthing.tray" pkgs
          platforms.linux)
      ];

      systemd.user.services = {
        "syncthingtray" = {
          Unit = {
            Description = "syncthingtray";
            Requires = [ "tray.target" ];
            After = [ "graphical-session-pre.target" "tray.target" ];
            PartOf = [ "graphical-session.target" ];
          };

          Service = {
            ExecStart = "${pkgs.syncthingtray-minimal}/bin/syncthingtray";
          };

          Install = { WantedBy = [ "graphical-session.target" ]; };
        };
      };
      warnings = [
        "Specifying 'services.syncthing.tray' as a boolean is deprecated, set 'services.syncthing.tray.enable' instead. See https://github.com/nix-community/home-manager/pull/1257."
      ];
    })
  ];
}
