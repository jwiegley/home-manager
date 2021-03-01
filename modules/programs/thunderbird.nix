{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.programs.thunderbird;

  thunderbirdConfigPath = ".thunderbird";

  profilesPath =  thunderbirdConfigPath;

  profiles = flip mapAttrs' cfg.profiles (_: profile:
    nameValuePair "Profile${toString profile.id}" {
      Name = profile.name;
      Path = profile.path;
      IsRelative = 1;
      Default = if profile.isDefault then 1 else 0;
    }) // {
      General = { StartWithLastProfile = 1; };
    };

  profilesIni = generators.toINI { } profiles;

  mkUserJs = prefs: extraPrefs: ''
    // Generated by Home Manager.

    ${concatStrings (mapAttrsToList (name: value: ''
      user_pref("${name}", ${builtins.toJSON value});
    '') prefs)}

    ${extraPrefs}
  '';

  filterFlags = {
    before-junk = 1;
    manually = 16;
    after-junk = 32;
    after-sending = 64;
    archiving = 128;
    every-10-min = 256;
  };

  mkDat = let
    toDatVal = val:
      if isBool val then (if val then "yes" else "no") else toString val;
    mkLine = { key, val }: ''
      ${key}="${toDatVal val}"
             '';
  in concatMapStrings mkLine;

  mkFilters = mail: f:
    let
      filtersCfg = f (msgFiltersLib mail);

      mkAction = { action, actionValue }:
        ([{
          key = "action";
          val = action;
        }] ++ (optional (actionValue != null) {
          key = "actionValue";
          val = actionValue;
        }));
      mkFilter = name: value:
        ([
          {
            key = "name";
            val = name;
          }
          {
            key = "enabled";
            val = value.enabled;
          }
          {
            key = "type";
            val = foldl' (a: b: a + b) 0 (value.when filterFlags);
          }
        ] ++ (concatMap mkAction value.actions) ++ [{
          key = "condition";
          val = value.condition;
        }]);
      msgFilterHeader = [
        {
          key = "version";
          val = 9;
        }
        {
          key = "logging";
          val = false;
        }
      ];
    in mkDat
    (msgFilterHeader ++ (flatten (mapAttrsToList mkFilter filtersCfg)));

  msgFiltersLib = mail:
    let
      # should work be enough for most mail addresses
      escapedMail = replaceChars [ "@" ] [ "%40" ] mail;
      mailHost = elemAt (builtins.split "@" mail) 2;
      conditions = op: cx: concatStringsSep " " (map (c: "${op} (${c})") cx);
      mkAction = action: actionValue: { inherit action actionValue; };
      mkFolder = pre: dir: "${pre}/${dir}";
    in {
      mark-read = mkAction "Mark read" null;
      move-to = mkAction "Move to folder";
      copy-to = mkAction "Copy to folder";
      imap-folder = mkFolder "imap://${escapedMail}@mail.${mailHost}";
      local-folder = mkFolder "mailbox://nobody@Local%20Folders/";
      forward-to = mkAction "Forward";
      change-priority = mkAction "Change priority";
      all = conditions "AND";
      any = conditions "OR";
    };

in {
  meta.maintainers = [ maintainers.chisui ];

  options = {
    programs.thunderbird = {
      enable = mkEnableOption "Thunderbird";

      package = mkOption {
        type = types.package;
        default = pkgs.thunderbird;
        defaultText = literalExample "pkgs.thunderbird";
        description = ''
          The Thunderbird package to use.
          this should be a wrapped Thunderbird package.
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
                  "browser.search.region" = "GB";
                  "browser.search.isUS" = false;
                  "general.useragent.locale" = "en-GB";
                }
              '';
              description = "Attribute set of Firefox preferences.";
            };

            accounts = mkOption {
              default = { };
              description = "Attribute set of mail account logins.";
              example = literalExample ''
                {
                  "some.address@homepage.net" = {
                    filters = msgFilters: with msgFilters; {
                      "move to work folder" = {
                        condition = all [ "from,ends-with,@work.com" ];
                        actions = [ (move-to (imap-folder "work")) ];
                      };
                    };
                  };
                }
              '';
              type = types.attrsOf (types.submodule ({ config, name, ... }: {
                options = {
                  filters = mkOption {
                    default = { };
                    description =
                      "Attribute set of mail filters. key is the filter name";
                    type = types.functionTo (types.attrsOf (types.submodule
                      ({ config, name, ... }: {
                        options = {
                          enabled = mkOption {
                            type = types.bool;
                            default = true;
                            description = "whether to enable this filter.";
                          };
                          when = mkOption {
                            type = types.functionTo (types.listOf types.int);
                            default = flags:
                              with flags; [
                                manually
                                before-junk
                              ];
                            example = literalExample
                              "flags: with flags; [ manually before-junk ]";
                            description = ''
                              When the filter should be applied.
                              This is stored as an int with certain bitflags. An attribute set with the corresponding bitflags is passed to the function.
                              The function has to return a list of all these flags.
                              </para><para>
                              Flags:
                              ${concatStrings (mapAttrsToList (name: value: ''
                                ${name} = ${toString value}
                              '') filterFlags)}
                            '';
                          };
                          condition = mkOption {
                            type = types.str;
                            description =
                              "filter conditions that all have to match for this filter to be applied. Either this option or `any` has to be present.";
                          };
                          actions = mkOption {
                            description = "filter actions";
                            type = types.listOf types.unspecified;
                          };
                        };
                      })));
                  };
                };
              }));
            };

            extensions = mkOption {
              type = types.listOf types.package;
              default = [ ];
              example = literalExample ''
                with pkgs.nur.repos.chisui.thunderbird-addons; [
                  TODO
                ]
              '';
              description = ''
                List of Thunderbird add-on packages to install for this profile. Some
                pre-packaged add-ons are accessible from NUR,
                <link xlink:href="https://github.com/nix-community/NUR"/>.
                Once you have NUR installed run

                <screen language="console">
                  <prompt>$</prompt> <userinput>nix-env -f '&lt;nixpkgs&gt;' -qaP -A nur.repos.chisui.thunderbird-addons</userinput>
                </screen>

                to list the available Thunderbird add-ons.

                </para><para>

                Note that it is necessary to manually enable these
                extensions inside Thunderbird after the first installation.

                </para><para>

                Extensions listed here will only be available in Firefox
                profiles managed through the
                <link linkend="opt-programs.thunderbird.profiles">programs.thunderbird.profiles</link>
                option. This is due to recent changes in the way Thunderbird
                handles extension side-loading.
              '';
            };

            extraConfig = mkOption {
              type = types.lines;
              default = "";
              description = ''
                Extra preferences to add to <filename>user.js</filename>.
              '';
            };

            userChrome = mkOption {
              type = types.lines;
              default = "";
              description = "Custom Thunderbird user chrome CSS.";
            };

            userContent = mkOption {
              type = types.lines;
              default = "";
              description = "Custom Thunderbird user content CSS.";
            };

            path = mkOption {
              type = types.str;
              default = name;
              description = "Profile path.";
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
    }] ++ flatten (flip mapAttrsToList cfg.profiles (_: profile:
      let profilePath = "${profilesPath}/${profile.path}";
      in [{
        "${profilePath}/.keep".text = "";

        "${profilePath}/chrome/userChrome.css" =
          mkIf (profile.userChrome != "") { text = profile.userChrome; };

        "${profilePath}/chrome/userContent.css" =
          mkIf (profile.userContent != "") { text = profile.userContent; };

        "${profilePath}/user.js" =
          mkIf (profile.settings != { } || profile.extraConfig != "") {
            text = mkUserJs profile.settings profile.extraConfig;
          };

        "${profilePath}/extensions" = let
          extensionsEnvPkg = pkgs.buildEnv {
            name = "hm-thunderbird-extensions-${toString profile.id}";
            paths = profile.extensions;
          };
        in mkIf (profile.extensions != [ ]) {
          source = "${extensionsEnvPkg}/share/thunderbird/extensions";
          recursive = true;
          force = true;
        };
      }] ++ flip mapAttrsToList profile.accounts (mail: account:
        let
          hostName = builtins.elemAt (builtins.split "@" mail) 2;
          imapMailPath = "${profilePath}/ImapMail/mail.${hostName}";
        in {
          "${imapMailPath}/msgFilterRules.dat" =
            mkIf (builtins.hasAttr "filters" account) {
              text = mkFilters mail account.filters;
            };
        }))));
  };
}
