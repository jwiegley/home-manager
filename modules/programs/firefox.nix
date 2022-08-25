{ config, lib, pkgs, ... }:

with lib;

let

  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  cfg = config.programs.firefox;

  mozillaConfigPath =
    if isDarwin then "Library/Application Support/Mozilla" else ".mozilla";

  firefoxConfigPath = if isDarwin then
    "Library/Application Support/Firefox"
  else
    "${mozillaConfigPath}/firefox";

  profilesPath =
    if isDarwin then "${firefoxConfigPath}/Profiles" else firefoxConfigPath;

  # The extensions path shared by all profiles; will not be supported
  # by future Firefox versions.
  extensionPath = "extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}";

  extensionsEnvPkg = pkgs.buildEnv {
    name = "hm-firefox-extensions";
    paths = cfg.extensions;
  };

  profiles = flip mapAttrs' cfg.profiles (_: profile:
    nameValuePair "Profile${toString profile.id}" {
      Name = profile.name;
      Path = if isDarwin then "Profiles/${profile.path}" else profile.path;
      IsRelative = 1;
      Default = if profile.isDefault then 1 else 0;
    }) // {
      General = { StartWithLastProfile = 1; };
    };

  profilesIni = generators.toINI { } profiles;

  mkUserJs = prefs: extraPrefs: bookmarks:
    let
      prefs' = lib.optionalAttrs ([ ] != bookmarks) {
        "browser.bookmarks.file" = toString (firefoxBookmarksFile bookmarks);
        "browser.places.importBookmarksHTML" = true;
      } // prefs;
    in ''
      // Generated by Home Manager.

      ${concatStrings (mapAttrsToList (name: value: ''
        user_pref("${name}", ${builtins.toJSON value});
      '') prefs')}

      ${extraPrefs}
    '';

  firefoxBookmarksFile = bookmarks:
    let
      indent = level:
        lib.concatStringsSep "" (map (lib.const "  ") (lib.range 1 level));

      bookmarkToHTML = indentLevel: bookmark:
        ''
          ${indent indentLevel}<DT><A HREF="${
            escapeXML bookmark.url
          }" ADD_DATE="0" LAST_MODIFIED="0"${
            lib.optionalString (bookmark.keyword != null)
            " SHORTCUTURL=\"${escapeXML bookmark.keyword}\""
          }>${escapeXML bookmark.name}</A>'';

      directoryToHTML = indentLevel: directory: ''
        ${indent indentLevel}<DT>${
          if directory.toolbar then
            ''<H3 PERSONAL_TOOLBAR_FOLDER="true">Bookmarks Toolbar''
          else
            "<H3>${escapeXML directory.name}"
        }</H3>
        ${indent indentLevel}<DL><p>
        ${allItemsToHTML (indentLevel + 1) directory.bookmarks}
        ${indent indentLevel}</p></DL>'';

      itemToHTMLOrRecurse = indentLevel: item:
        if item ? "url" then
          bookmarkToHTML indentLevel item
        else
          directoryToHTML indentLevel item;

      allItemsToHTML = indentLevel: bookmarks:
        lib.concatStringsSep "\n"
        (map (itemToHTMLOrRecurse indentLevel) bookmarks);

      bookmarkEntries = allItemsToHTML 1 bookmarks;
    in pkgs.writeText "firefox-bookmarks.html" ''
      <!DOCTYPE NETSCAPE-Bookmark-file-1>
      <!-- This is an automatically generated file.
        It will be read and overwritten.
        DO NOT EDIT! -->
      <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
      <TITLE>Bookmarks</TITLE>
      <H1>Bookmarks Menu</H1>
      <DL><p>
      ${bookmarkEntries}
      </p></DL>
    '';

in {
  meta.maintainers = [ maintainers.rycee ];

  imports = [
    (mkRemovedOptionModule [ "programs" "firefox" "enableAdobeFlash" ]
      "Support for this option has been removed.")
    (mkRemovedOptionModule [ "programs" "firefox" "enableGoogleTalk" ]
      "Support for this option has been removed.")
    (mkRemovedOptionModule [ "programs" "firefox" "enableIcedTea" ]
      "Support for this option has been removed.")
  ];

  options = {
    programs.firefox = {
      enable = mkEnableOption "Firefox";

      package = mkOption {
        type = types.package;
        default = if versionAtLeast config.home.stateVersion "19.09" then
          pkgs.firefox
        else
          pkgs.firefox-unwrapped;
        defaultText = literalExpression "pkgs.firefox";
        example = literalExpression ''
          pkgs.firefox.override {
            # See nixpkgs' firefox/wrapper.nix to check which options you can use
            cfg = {
              # Gnome shell native connector
              enableGnomeExtensions = true;
              # Tridactyl native connector
              enableTridactylNative = true;
            };
          }
        '';
        description = ''
          The Firefox package to use. If state version ≥ 19.09 then
          this should be a wrapped Firefox package. For earlier state
          versions it should be an unwrapped Firefox package.
        '';
      };

      extensions = mkOption {
        type = types.listOf types.package;
        default = [ ];
        example = literalExpression ''
          with pkgs.nur.repos.rycee.firefox-addons; [
            https-everywhere
            privacy-badger
          ]
        '';
        description = ''
          List of Firefox add-on packages to install. Some
          pre-packaged add-ons are accessible from NUR,
          <link xlink:href="https://github.com/nix-community/NUR"/>.
          Once you have NUR installed run

          <screen language="console">
            <prompt>$</prompt> <userinput>nix-env -f '&lt;nixpkgs&gt;' -qaP -A nur.repos.rycee.firefox-addons</userinput>
          </screen>

          to list the available Firefox add-ons.

          </para><para>

          Note that it is necessary to manually enable these
          extensions inside Firefox after the first installation.

          </para><para>

          Extensions listed here will only be available in Firefox
          profiles managed through the
          <xref linkend="opt-programs.firefox.profiles"/>
          option. This is due to recent changes in the way Firefox
          handles extension side-loading.
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
              example = literalExpression ''
                {
                  "browser.startup.homepage" = "https://nixos.org";
                  "browser.search.region" = "GB";
                  "browser.search.isUS" = false;
                  "distribution.searchplugins.defaultLocale" = "en-GB";
                  "general.useragent.locale" = "en-GB";
                  "browser.bookmarks.showMobileBookmarks" = true;
                }
              '';
              description = "Attribute set of Firefox preferences.";
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
              description = "Custom Firefox user chrome CSS.";
              example = ''
                /* Hide tab bar in FF Quantum */
                @-moz-document url("chrome://browser/content/browser.xul") {
                  #TabsToolbar {
                    visibility: collapse !important;
                    margin-bottom: 21px !important;
                  }

                  #sidebar-box[sidebarcommand="treestyletab_piro_sakura_ne_jp-sidebar-action"] #sidebar-header {
                    visibility: collapse !important;
                  }
                }
              '';
            };

            userContent = mkOption {
              type = types.lines;
              default = "";
              description = "Custom Firefox user content CSS.";
              example = ''
                /* Hide scrollbar in FF Quantum */
                *{scrollbar-width:none !important}
              '';
            };

            bookmarks = mkOption {
              type = let
                bookmarkSubmodule = types.submodule ({ config, name, ... }: {
                  options = {
                    name = mkOption {
                      type = types.str;
                      default = name;
                      description = "Bookmark name.";
                    };

                    keyword = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Bookmark search keyword.";
                    };

                    url = mkOption {
                      type = types.str;
                      description = "Bookmark url, use %s for search terms.";
                    };
                  };
                }) // {
                  description = "bookmark submodule";
                };

                bookmarkType = types.addCheck bookmarkSubmodule (x: x ? "url");

                directoryType = types.submodule ({ config, name, ... }: {
                  options = {
                    name = mkOption {
                      type = types.str;
                      default = name;
                      description = "Directory name.";
                    };

                    bookmarks = mkOption {
                      type = types.listOf bookmarkType;
                      default = [ ];
                      description = "Bookmarks within directory.";
                    };

                    toolbar = mkOption {
                      type = types.bool;
                      default = false;
                      description = "If directory should be shown in toolbar.";
                    };
                  };
                }) // {
                  description = "directory submodule";
                };

                nodeType = types.either bookmarkType directoryType;
              in with types;
              coercedTo (attrsOf nodeType) attrValues (listOf nodeType);
              default = [ ];
              example = literalExpression ''
                [
                  {
                    name = "wikipedia";
                    keyword = "wiki";
                    url = "https://en.wikipedia.org/wiki/Special:Search?search=%s&go=Go";
                  }
                  {
                    name = "kernel.org";
                    url = "https://www.kernel.org";
                  }
                  {
                    name = "Nix sites";
                    bookmarks = [
                      {
                        name = "homepage";
                        url = "https://nixos.org/";
                      }
                      {
                        name = "wiki";
                        url = "https://nixos.wiki/";
                      }
                    ];
                  }
                ]
              '';
              description = ''
                Preloaded bookmarks. Note, this may silently overwrite any
                previously existing bookmarks!
              '';
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
        description = "Attribute set of Firefox profiles.";
      };

      enableGnomeExtensions = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to enable the GNOME Shell native host connector. Note, you
          also need to set the NixOS option
          <literal>services.gnome3.chrome-gnome-shell.enable</literal> to
          <literal>true</literal>.
        '';
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
        message = "Must have exactly one default Firefox profile but found "
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
          Must not have Firefox profiles with duplicate IDs but
        '' + concatStringsSep "\n" (mapAttrsToList mkMsg duplicates);
      })
    ];

    warnings = optional (cfg.enableGnomeExtensions or false) ''
      Using 'programs.firefox.enableGnomeExtensions' has been deprecated and
      will be removed in the future. Please change to overriding the package
      configuration using 'programs.firefox.package' instead. You can refer to
      its example for how to do this.
    '';

    home.packages = let
      # The configuration expected by the Firefox wrapper.
      fcfg = { enableGnomeExtensions = cfg.enableGnomeExtensions; };

      # A bit of hackery to force a config into the wrapper.
      browserName = cfg.package.browserName or (builtins.parseDrvName
        cfg.package.name).name;

      # The configuration expected by the Firefox wrapper builder.
      bcfg = setAttrByPath [ browserName ] fcfg;

      package = if isDarwin then
        cfg.package
      else if versionAtLeast config.home.stateVersion "19.09" then
        cfg.package.override (old: { cfg = old.cfg or { } // fcfg; })
      else
        (pkgs.wrapFirefox.override { config = bcfg; }) cfg.package { };
    in [ package ];

    home.file = mkMerge ([{
      "${mozillaConfigPath}/${extensionPath}" = mkIf (cfg.extensions != [ ]) {
        source = "${extensionsEnvPkg}/share/mozilla/${extensionPath}";
        recursive = true;
      };

      "${firefoxConfigPath}/profiles.ini" =
        mkIf (cfg.profiles != { }) { text = profilesIni; };
    }] ++ flip mapAttrsToList cfg.profiles (_: profile: {
      "${profilesPath}/${profile.path}/.keep".text = "";

      "${profilesPath}/${profile.path}/chrome/userChrome.css" =
        mkIf (profile.userChrome != "") { text = profile.userChrome; };

      "${profilesPath}/${profile.path}/chrome/userContent.css" =
        mkIf (profile.userContent != "") { text = profile.userContent; };

      "${profilesPath}/${profile.path}/user.js" = mkIf (profile.settings != { }
        || profile.extraConfig != "" || profile.bookmarks != [ ]) {
          text =
            mkUserJs profile.settings profile.extraConfig profile.bookmarks;
        };

      "${profilesPath}/${profile.path}/extensions" =
        mkIf (cfg.extensions != [ ]) {
          source = "${extensionsEnvPkg}/share/mozilla/${extensionPath}";
          recursive = true;
          force = true;
        };
    }));
  };
}
