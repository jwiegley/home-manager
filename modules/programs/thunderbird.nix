{ config, lib, pkgs, ... }:

with lib;

let

  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  cfg = config.programs.thunderbird;

  thunderbirdConfigPath = if isDarwin then
    "Library/Application Support/Thunderbird"
  else
    ".thunderbird";

  profiles = flip mapAttrs' cfg.profiles (_: profile:
    nameValuePair "Profile${toString profile.id}" {
      Name = profile.name;
      Path = if isDarwin then "Profiles/${profile.path}" else profile.path;
      IsRelative = 1;
      Default = if profile.isDefault then 1 else 0;
    }) // {
      General = {
        StartWithLastProfile = 1;
        Version = 2;
      };
    };

  profilesIni = generators.toINI { } profiles;

  mkUserJs = profile:
    let
      prefs = lib.optionalAttrs profile.disableTelemetry {
        "datareporting.healthreport.uploadEnabled" = false;
        "datareporting.policy.dataSubmissionPolicyAcceptedVersion" = 1;
        "dom.security.unexpected_system_load_telemetry_enabled" = false;
        "network.trr.confirmation_telemetry_enabled" = false;
        "toolkit.telemetry.archive.enabled" = false;
        "toolkit.telemetry.bhrPing.enabled" = false;
        "toolkit.telemetry.firstShutdownPing.enabled" = false;
        "toolkit.telemetry.newProfilePing.enabled" = false;
        "toolkit.telemetry.server" = "";
        "toolkit.telemetry.shutdownPingSender.enabled" = false;
        "toolkit.telemetry.unified" = false;
        "toolkit.telemetry.updatePing.enabled" = false;
      } // profile.settings;
    in ''
      // Generated by Home Manager.

      ${concatStrings (mapAttrsToList (name: value: ''
        user_pref("${name}", ${builtins.toJSON value});
      '') prefs)}

      ${profile.extraConfig}
    '';

in {
  meta.maintainers = [ maintainers.jkarlson ];

  options = {
    programs.thunderbird = {
      enable = mkEnableOption
        "Thunderbird, a free, open-source, cross-platform application for managing email, news feeds, chat, and news groups";

      package = mkOption {
        type = types.package;
        default = pkgs.thunderbird;
        defaultText = literalExample "pkgs.thunderbird";
        description = ''
          The Thunderbird package to use.
        '';
      };

      profiles = mkOption {
        type = types.attrsOf (types.submodule ({ config, name, ... }: {
          options = {
            name = mkOption {
              type = types.str;
              default = name;
              description = "Profile name.";
            };

            id = mkOption {
              type = types.ints.unsigned;
              default = 0;
              description = ''
                Profile ID. This should be set to a unique number per profile.
              '';
            };

            settings = mkOption {
              type = with types; attrsOf (either bool (either int str));
              default = { };
              example = literalExample ''
                {
                  "mail.smtpserver.smtp_iki.authMethod" = 4;
                  "mail.smtpserver.smtp_iki.hostname" = "smtp.iki.fi";
                  "mail.smtpserver.smtp_iki.port" = 587;
                  "mail.smtpserver.smtp_iki.try_ssl" = 2;
                }
              '';
              description = "Attribute set of Thunderbird preferences.";
            };

            extraConfig = mkOption {
              type = types.lines;
              default = "";
              description = ''
                Extra preferences to add to <filename>user.js</filename>.
              '';
            };

            path = mkOption {
              type = types.str;
              default = name;
              description = "Profile path.";
            };

            disableTelemetry = mkOption {
              type = types.bool;
              default = false;
              description = "Disable telemetry for this profile.";
            };

            isDefault = mkOption {
              type = types.bool;
              default = config.id == 0;
              defaultText = "true if profile ID is 0";
              description = "Whether this is a default profile.";
            };
          };
        }));
        default = { };
        description = "Attribute set of Thunderbird profiles.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      (let
        defaults =
          catAttrs "name" (filter (a: a.isDefault) (attrValues cfg.profiles));
      in {
        assertion = cfg.profiles == { } || length defaults == 1;
        message = "Must have exactly one default Thunderbird profile but found "
          + toString (length defaults) + optionalString (length defaults > 1)
          (", namely " + concatStringsSep ", " defaults);
      })

      (let
        duplicates = filterAttrs (_: v: length v != 1) (zipAttrs
          (mapAttrsToList (n: v: { "${toString v.id}" = n; }) (cfg.profiles)));

        mkMsg = n: v: "  - ID ${n} is used by ${concatStringsSep ", " v}";
      in {
        assertion = duplicates == { };
        message = ''
          Must not have Thunderbird profiles with duplicate IDs but
        '' + concatStringsSep "\n" (mapAttrsToList mkMsg duplicates);
      })
    ];

    home.packages = [ cfg.package ];

    home.file = mkMerge ([{
      "${thunderbirdConfigPath}/profiles.ini" =
        mkIf (cfg.profiles != { }) { text = profilesIni; };
    }] ++ flip mapAttrsToList cfg.profiles (_: profile: {
      "${thunderbirdConfigPath}/${profile.path}/.keep".text = "";

      "${thunderbirdConfigPath}/${profile.path}/user.js" =
        mkIf (profile.settings != { } || profile.extraConfig != "") {
          text = mkUserJs profile;
        };
    }));
  };
}
