{ config, lib, pkgs, ... }:

with lib;

let

  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  cfg = config.programs.firefox;

  jsonFormat = pkgs.formats.json { };

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

  userPrefValue = pref:
    builtins.toJSON (if isBool pref || isInt pref || isString pref then
      pref
    else
      builtins.toJSON pref);

  mkUserJs = prefs: extraPrefs: bookmarks:
    let
      prefs' = lib.optionalAttrs ([ ] != bookmarks) {
        "browser.bookmarks.file" = toString (firefoxBookmarksFile bookmarks);
        "browser.places.importBookmarksHTML" = true;
      } // prefs;
    in ''
      // Generated by Home Manager.

      ${concatStrings (mapAttrsToList (name: value: ''
        user_pref("${name}", ${userPrefValue value});
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
          }${
            lib.optionalString (bookmark.tags != [ ])
            " TAGS=\"${escapeXML (concatStringsSep "," bookmark.tags)}\""
          }>${escapeXML bookmark.name}</A>'';

      directoryToHTML = indentLevel: directory: ''
        ${indent indentLevel}<DT>
          <H3>${escapeXML directory.name}</H3>
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

      splitEntries = partition (b: b.toolbar) bookmarks;

    in pkgs.writeText "firefox-bookmarks.html" (''
      <!DOCTYPE NETSCAPE-Bookmark-file-1>
      <!-- This is an automatically generated file.
        It will be read and overwritten.
        DO NOT EDIT! -->
      <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
      <TITLE>Bookmarks</TITLE>
      <H1>Bookmarks Menu</H1>

      <DL><p>
        ${allItemsToHTML 1 splitEntries.wrong}
    '' + (lib.optionalString (length splitEntries.right > 0) ''
      <DT><H3 PERSONAL_TOOLBAR_FOLDER="true">Bookmarks Toolbar</H3>
      <DL><p>
        ${allItemsToHTML 1 splitEntries.right}
      </p></DL>
    '') + ''
      </p></DL>
    '');

in {
  meta.maintainers = [ maintainers.rycee maintainers.kira-bruneau ];

  imports = [
    (mkRemovedOptionModule [ "programs" "firefox" "extensions" ] ''

      Extensions are now managed per-profile. That is, change from

        programs.firefox.extensions = [ foo bar ];

      to

        programs.firefox.profiles.myprofile.extensions = [ foo bar ];'')
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
              type = types.attrsOf (jsonFormat.type // {
                description =
                  "Firefox preference (int, bool, string, and also attrs, list, float as a JSON string)";
              });
              default = { };
              example = literalExpression ''
                {
                  "browser.startup.homepage" = "https://nixos.org";
                  "browser.search.region" = "GB";
                  "browser.search.isUS" = false;
                  "distribution.searchplugins.defaultLocale" = "en-GB";
                  "general.useragent.locale" = "en-GB";
                  "browser.bookmarks.showMobileBookmarks" = true;
                  "browser.newtabpage.pinned" = [{
                    title = "NixOS";
                    url = "https://nixos.org";
                  }];
                }
              '';
              description = ''
                Attribute set of Firefox preferences.

                Firefox only supports int, bool, and string types for
                preferences, but home-manager will automatically
                convert all other JSON-compatible values into strings.
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

                    tags = mkOption {
                      type = types.listOf types.str;
                      default = [ ];
                      description = "Bookmark tags.";
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

                    toolbar = mkOption {
                      type = types.bool;
                      default = false;
                      description = "If bookmark should be shown in toolbar.";
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
                      type = types.listOf nodeType;
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
                    tags = [ "wiki" ];
                    keyword = "wiki";
                    url = "https://en.wikipedia.org/wiki/Special:Search?search=%s&go=Go";
                  }
                  {
                    name = "kernel.org";
                    url = "https://www.kernel.org";
                  }
                  {
                    name = "Nix sites";
                    toolbar = true;
                    bookmarks = [
                      {
                        name = "homepage";
                        url = "https://nixos.org/";
                      }
                      {
                        name = "wiki";
                        tags = [ "wiki" "nix" ];
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

            search = {
              force = mkOption {
                type = with types; bool;
                default = false;
                description = ''
                  Whether to force replace the existing search
                  configuration. This is recommended since Firefox will
                  replace the symlink for the search configuration on every
                  launch, but note that you'll lose any existing
                  configuration by enabling this.
                '';
              };

              default = mkOption {
                type = with types; nullOr str;
                default = null;
                example = "DuckDuckGo";
                description = ''
                  The default search engine used in the address bar and search bar.
                '';
              };

              order = mkOption {
                type = with types; uniq (listOf str);
                default = [ ];
                example = [ "DuckDuckGo" "Google" ];
                description = ''
                  The order the search engines are listed in. Any engines
                  that aren't included in this list will be listed after
                  these in an unspecified order.
                '';
              };

              engines = mkOption {
                type = with types; attrsOf (attrsOf jsonFormat.type);
                default = { };
                example = literalExpression ''
                  {
                    "Nix Packages" = {
                      urls = [{
                        template = "https://search.nixos.org/packages";
                        params = [
                          { name = "type"; value = "packages"; }
                          { name = "query"; value = "{searchTerms}"; }
                        ];
                      }];

                      icon = "''${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
                      definedAliases = [ "@np" ];
                    };

                    "NixOS Wiki" = {
                      urls = [{ template = "https://nixos.wiki/index.php?search={searchTerms}"; }];
                      iconUpdateURL = "https://nixos.wiki/favicon.png";
                      updateInterval = 24 * 60 * 60 * 1000; # every day
                      definedAliases = [ "@nw" ];
                    };

                    "Bing".metaData.hidden = true;
                    "Google".metaData.alias = "@g"; # builtin engines only support specifying one additional alias
                  }
                '';
                description = ''
                  Attribute set of search engine configurations. Engines
                  that only have <varname>metaData</varname> specified will
                  be treated as builtin to Firefox.
                  </para><para>
                  See <link xlink:href=
                  "https://searchfox.org/mozilla-central/rev/669329e284f8e8e2bb28090617192ca9b4ef3380/toolkit/components/search/SearchEngine.jsm#1138-1177">SearchEngine.jsm</link>
                  in Firefox's source for available options. We maintain a
                  mapping to let you specify all options in the referenced
                  link without underscores, but it may fall out of date with
                  future options.
                  </para><para>
                  Note, <varname>icon</varname> is also a special option
                  added by Home Manager to make it convenient to specify
                  absolute icon paths.
                '';
              };
            };

            extensions = mkOption {
              type = types.listOf types.package;
              default = [ ];
              example = literalExpression ''
                with pkgs.nur.repos.rycee.firefox-addons; [
                  privacy-badger
                ]
              '';
              description = ''
                List of Firefox add-on packages to install for this profile.
                Some pre-packaged add-ons are accessible from NUR,
                <link xlink:href="https://github.com/nix-community/NUR"/>.
                Once you have NUR installed run

                <screen language="console">
                  <prompt>$</prompt> <userinput>nix-env -f '&lt;nixpkgs&gt;' -qaP -A nur.repos.rycee.firefox-addons</userinput>
                </screen>

                to list the available Firefox add-ons.

                </para><para>

                Note that it is necessary to manually enable these extensions
                inside Firefox after the first installation.
              '';
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
          <literal>services.gnome.gnome-browser-connector.enable</literal> to
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

      "${profilesPath}/${profile.path}/search.json.mozlz4" = mkIf
        (profile.search.default != null || profile.search.order != [ ]
          || profile.search.engines != { }) {
            force = profile.search.force;
            source = let
              settings = {
                version = 6;
                engines = let
                  # Map of nice field names to internal field names.
                  # This is intended to be exhaustive and should be
                  # updated at every version bump.
                  internalFieldNames = (genAttrs [
                    "name"
                    "isAppProvided"
                    "loadPath"
                    "hasPreferredIcon"
                    "updateInterval"
                    "updateURL"
                    "iconUpdateURL"
                    "iconURL"
                    "iconMapObj"
                    "metaData"
                    "orderHint"
                    "definedAliases"
                    "urls"
                  ] (name: "_${name}")) // {
                    searchForm = "__searchForm";
                  };

                  processCustomEngineInput = input:
                    (removeAttrs input [ "icon" ])
                    // optionalAttrs (input ? icon) {
                      # Convenience to specify absolute path to icon
                      iconURL = "file://${input.icon}";
                    } // (optionalAttrs (input ? iconUpdateURL) {
                      # Convenience to default iconURL to iconUpdateURL so
                      # the icon is immediately downloaded from the URL
                      iconURL = input.iconURL or input.iconUpdateURL;
                    } // {
                      # Required for custom engine configurations, loadPaths
                      # are unique identifiers that are generally formatted
                      # like: [source]/path/to/engine.xml
                      loadPath = ''
                        [home-manager]/programs.firefox.profiles.${profile.name}.search.engines."${
                          replaceStrings [ "\\" ] [ "\\\\" ] input.name
                        }"'';
                    });

                  processEngineInput = name: input:
                    let
                      requiredInput = {
                        inherit name;
                        isAppProvided = input.isAppProvided or removeAttrs input
                          [ "metaData" ] == { };
                        metaData = input.metaData or { };
                      };
                    in if requiredInput.isAppProvided then
                      requiredInput
                    else
                      processCustomEngineInput (input // requiredInput);

                  buildEngineConfig = name: input:
                    mapAttrs' (name: value: {
                      name = internalFieldNames.${name} or name;
                      inherit value;
                    }) (processEngineInput name input);

                  sortEngineConfigs = configs:
                    let
                      buildEngineConfigWithOrder = order: name:
                        let
                          config = configs.${name} or {
                            _name = name;
                            _isAppProvided = true;
                            _metaData = { };
                          };
                        in config // {
                          _metaData = config._metaData // { inherit order; };
                        };

                      engineConfigsWithoutOrder =
                        attrValues (removeAttrs configs profile.search.order);

                      sortedEngineConfigs =
                        (imap buildEngineConfigWithOrder profile.search.order)
                        ++ engineConfigsWithoutOrder;
                    in sortedEngineConfigs;

                  engineInput = profile.search.engines // {
                    # Infer profile.search.default as an app provided
                    # engine if it's not in profile.search.engines
                    ${profile.search.default} =
                      profile.search.engines.${profile.search.default} or { };
                  };
                in sortEngineConfigs (mapAttrs buildEngineConfig engineInput);

                metaData = optionalAttrs (profile.search.default != null) {
                  current = profile.search.default;
                  hash = "@hash@";
                } // {
                  useSavedOrder = profile.search.order != [ ];
                };
              };

              # Home Manager doesn't circumvent user consent and isn't acting
              # maliciously. We're modifying the search outside of Firefox, but
              # a claim by Mozilla to remove this would be very anti-user, and
              # is unlikely to be an issue for our use case.
              disclaimer = appName:
                "By modifying this file, I agree that I am doing so "
                + "only within ${appName} itself, using official, user-driven search "
                + "engine selection processes, and in a way which does not circumvent "
                + "user consent. I acknowledge that any attempt to change this file "
                + "from outside of ${appName} is a malicious act, and will be responded "
                + "to accordingly.";

              salt = if profile.search.default != null then
                profile.path + profile.search.default + disclaimer "Firefox"
              else
                null;
            in pkgs.runCommand "search.json.mozlz4" {
              nativeBuildInputs = with pkgs; [ mozlz4a openssl ];
              json = builtins.toJSON settings;
              inherit salt;
            } ''
              if [[ -n $salt ]]; then
                export hash=$(echo -n "$salt" | openssl dgst -sha256 -binary | base64)
                mozlz4a <(substituteStream json search.json.in --subst-var hash) "$out"
              else
                mozlz4a <(echo "$json") "$out"
              fi
            '';
          };

      "${profilesPath}/${profile.path}/extensions" =
        mkIf (profile.extensions != [ ]) {
          source = let
            extensionsEnvPkg = pkgs.buildEnv {
              name = "hm-firefox-extensions";
              paths = profile.extensions;
            };
          in "${extensionsEnvPkg}/share/mozilla/${extensionPath}";
          recursive = true;
          force = true;
        };
    }));
  };
}
