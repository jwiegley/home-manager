{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.programs.git;

  # create [section "subsection"] keys from "section.subsection" attrset names
  mkSectionName = name:
    let
      containsQuote = strings.hasInfix ''"'' name;
      sections = splitString "." name;
      section = head sections;
      subsections = tail sections;
      subsection = concatStringsSep "." subsections;
    in if containsQuote || subsections == [ ] then
      name
    else
      ''${section} "${subsection}"'';

  mkValueString = v:
    let
      escapedV = ''
        "${
          replaceStrings [ "\n" "	" ''"'' "\\" ] [ "\\n" "\\t" ''\"'' "\\\\" ] v
        }"'';
    in generators.mkValueStringDefault { } (if isString v then escapedV else v);

  # generation for multiple ini values
  mkKeyValue = k: v:
    let
      mkKeyValue =
        generators.mkKeyValueDefault { inherit mkValueString; } " = " k;
    in concatStringsSep "\n" (map (kv: "	" + mkKeyValue kv) (toList v));

  # converts { a.b.c = 5; } to { "a.b".c = 5; } for toINI
  gitFlattenAttrs = let
    recurse = path: value:
      if isAttrs value then
        mapAttrsToList (name: value: recurse ([ name ] ++ path) value) value
      else if length path > 1 then {
        ${concatStringsSep "." (reverseList (tail path))}.${head path} = value;
      } else {
        ${head path} = value;
      };
  in attrs: foldl recursiveUpdate { } (flatten (recurse [ ] attrs));

  gitToIni = attrs:
    let toIni = generators.toINI { inherit mkKeyValue mkSectionName; };
    in toIni (gitFlattenAttrs attrs);

  gitIniType = with types;
    let
      primitiveType = either str (either bool int);
      multipleType = either primitiveType (listOf primitiveType);
      sectionType = attrsOf multipleType;
      supersectionType = attrsOf (either multipleType sectionType);
    in attrsOf supersectionType;

  signModule = types.submodule {
    imports = [ (mkRenamedOptionModule [ "gpgPath" ] [ "program" ]) ];
    options = {
      signByDefault = mkOption {
        type = types.bool;
        default = false;
        description = "Whether commits and tags should be signed by default.";
      };
      format = mkOption {
        type = types.nullOr (types.enum [ "openpgp" "ssh" "x509" ]);
        default = null;
        description = ''
          The signing method to use when signing commits and tags.
          Currently supports OpenPGP/GnuPG keys, SSH keys and X.509 certificates.
        '';
      };
      key = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          The default signing key fingerprint.
          </para><para>
          Set to <literal>null</literal> to let the signer program decide which signing key
          to use depending on commit’s author.
        '';
      };
      program = mkOption {
        type = types.str;
        defaultText = ''
          With OpenPGP/GnuPG: ''${pkgs.gnupg}/bin/gpg2
          With SSH: ''${pkgs.openssh}/bin/ssh
          With X.509: ''${pkgs.gnupg}/bin/gpgsm
        '';
        description = "Path to the signer binary.";
      };
    };
  };

  includeModule = types.submodule ({ config, ... }: {
    options = {
      condition = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Include this configuration only when <varname>condition</varname>
          matches. Allowed conditions are described in
          <citerefentry>
            <refentrytitle>git-config</refentrytitle>
            <manvolnum>1</manvolnum>
          </citerefentry>.
        '';
      };

      path = mkOption {
        type = with types; either str path;
        description = "Path of the configuration file to include.";
      };

      contents = mkOption {
        type = types.attrsOf types.anything;
        default = { };
        example = literalExpression ''
          {
            user = {
              email = "bob@work.example.com";
              name = "Bob Work";
              signingKey = "1A2B3C4D5E6F7G8H";
            };
            commit = {
              gpgSign = true;
            };
          };
        '';
        description = ''
          Configuration to include. If empty then a path must be given.

          This follows the configuration structure as described in
          <citerefentry>
            <refentrytitle>git-config</refentrytitle>
            <manvolnum>1</manvolnum>
          </citerefentry>.
        '';
      };

      contentSuffix = mkOption {
        type = types.str;
        default = "gitconfig";
        description = ''
          Nix store name for the git configuration text file,
          when generating the configuration text from nix options.
        '';
      };
    };
    config.path = mkIf (config.contents != { }) (mkDefault
      (pkgs.writeText (hm.strings.storeFileName config.contentSuffix)
        (gitToIni config.contents)));
  });

  assertAtMostOneIsSet = attrs: options:
    let
      enabled = builtins.map (path: lib.attrByPath path false attrs) options;
      paths =
        builtins.map (path: "'programs.git.${lib.concatStringsSep "." path}'")
        options;
    in {
      assertion = count id enabled <= 1;
      message = "At most one of ${
          lib.concatStringsSep ", " paths
        } can be set to true at the same time.";
    };
in {
  meta.maintainers = [ maintainers.rycee ];

  options = {
    programs.git = {
      enable = mkEnableOption "Git";

      package = mkOption {
        type = types.package;
        default = pkgs.git;
        defaultText = literalExpression "pkgs.git";
        description = ''
          Git package to install. Use <varname>pkgs.gitAndTools.gitFull</varname>
          to gain access to <command>git send-email</command> for instance.
        '';
      };

      userName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Default user name to use.";
      };

      userEmail = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Default user email to use.";
      };

      aliases = mkOption {
        type = types.attrsOf types.str;
        default = { };
        example = { co = "checkout"; };
        description = "Git aliases to define.";
      };

      signing = mkOption {
        type = types.nullOr signModule;
        default = null;
        description = "Options related to signing commits and tags.";
      };

      extraConfig = mkOption {
        type = types.either types.lines gitIniType;
        default = { };
        example = {
          core = { whitespace = "trailing-space,space-before-tab"; };
          url."ssh://git@host".insteadOf = "otherhost";
        };
        description = ''
          Additional configuration to add. The use of string values is
          deprecated and will be removed in the future.
        '';
      };

      hooks = mkOption {
        type = types.attrsOf types.path;
        default = { };
        example = literalExpression ''
          {
            pre-commit = ./pre-commit-script;
          }
        '';
        description = ''
          Configuration helper for Git hooks.
          See <link xlink:href="https://git-scm.com/docs/githooks" />
          for reference.
        '';
      };

      iniContent = mkOption {
        type = gitIniType;
        internal = true;
      };

      ignores = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "*~" "*.swp" ];
        description = "List of paths that should be globally ignored.";
      };

      attributes = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "*.pdf diff=pdf" ];
        description = "List of defining attributes set globally.";
      };

      includes = mkOption {
        type = types.listOf includeModule;
        default = [ ];
        example = literalExpression ''
          [
            { path = "~/path/to/config.inc"; }
            {
              path = "~/path/to/conditional.inc";
              condition = "gitdir:~/src/dir";
            }
          ]
        '';
        description = "List of configuration files to include.";
      };

      lfs = {
        enable = mkEnableOption "Git Large File Storage";

        skipSmudge = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Skip automatic downloading of objects on clone or pull.
            This requires a manual <command>git lfs pull</command>
            every time a new commit is checked out on your repository.
          '';
        };
      };

      difftastic = {
        enable = mkEnableOption "" // {
          description = ''
            Enable the <command>difftastic</command> syntax highlighter.
            See <link xlink:href="https://github.com/Wilfred/difftastic" />.
          '';
        };

        background = mkOption {
          type = types.enum [ "light" "dark" ];
          default = "light";
          example = "dark";
          description = ''
            Determines whether difftastic should use the lighter or darker colors
            for syntax highlighting.
          '';
        };

        color = mkOption {
          type = types.enum [ "always" "auto" "never" ];
          default = "auto";
          example = "always";
          description = ''
            Determines when difftastic should color its output.
          '';
        };

        display = mkOption {
          type =
            types.enum [ "side-by-side" "side-by-side-show-both" "inline" ];
          default = "side-by-side";
          example = "inline";
          description = ''
            Determines how the output displays - in one column or two columns.
          '';
        };
      };

      delta = {
        enable = mkEnableOption "" // {
          description = ''
            Whether to enable the <command>delta</command> syntax highlighter.
            See <link xlink:href="https://github.com/dandavison/delta" />.
          '';
        };

        package = mkPackageOption pkgs "delta" { };

        options = mkOption {
          type = with types;
            let
              primitiveType = either str (either bool int);
              sectionType = attrsOf primitiveType;
            in attrsOf (either primitiveType sectionType);
          default = { };
          example = {
            features = "decorations";
            whitespace-error-style = "22 reverse";
            decorations = {
              commit-decoration-style = "bold yellow box ul";
              file-style = "bold yellow ul";
              file-decoration-style = "none";
            };
          };
          description = ''
            Options to configure delta.
          '';
        };
      };

      diff-so-fancy = {
        enable = mkEnableOption "" // {
          description = ''
            Enable the <command>diff-so-fancy</command> diff colorizer.
            See <link xlink:href="https://github.com/so-fancy/diff-so-fancy" />.
          '';
        };

        pagerOpts = mkOption {
          type = types.listOf types.str;
          default = [ "--tabs=4" "-RFX" ];
          description = ''
            Arguments to be passed to <command>less</command>.
          '';
        };

        markEmptyLines = mkOption {
          type = types.bool;
          default = true;
          example = false;
          description = ''
            Whether the first block of an empty line should be colored.
          '';
        };

        changeHunkIndicators = mkOption {
          type = types.bool;
          default = true;
          example = false;
          description = ''
            Simplify git header chunks to a more human readable format.
          '';
        };

        stripLeadingSymbols = mkOption {
          type = types.bool;
          default = true;
          example = false;
          description = ''
            Whether the <literal>+</literal> or <literal>-</literal> at
            line-start should be removed.
          '';
        };

        useUnicodeRuler = mkOption {
          type = types.bool;
          default = true;
          example = false;
          description = ''
            By default, the separator for the file header uses Unicode
            line-drawing characters. If this is causing output errors on
            your terminal, set this to false to use ASCII characters instead.
          '';
        };

        rulerWidth = mkOption {
          type = types.nullOr types.int;
          default = null;
          example = false;
          description = ''
            By default, the separator for the file header spans the full
            width of the terminal. Use this setting to set the width of
            the file header manually.
          '';
        };
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      home.packages = [ cfg.package ];
      assertions = [
        (assertAtMostOneIsSet cfg (builtins.map (tool: [ tool "enable" ]) [
          "delta"
          "diff-so-fancy"
          "difftastic"
        ]))
      ];
      warnings = if (cfg.signing.gpgPath or "") != "" then [''
        `programs.git.signing.gpgPath` has been deprecated.
        Please use `programs.git.signing.program` instead.
      ''] else
        [ ];

      programs.git.iniContent.user = {
        name = mkIf (cfg.userName != null) cfg.userName;
        email = mkIf (cfg.userEmail != null) cfg.userEmail;
      };

      xdg.configFile = {
        "git/config".text = gitToIni cfg.iniContent;

        "git/ignore" = mkIf (cfg.ignores != [ ]) {
          text = concatStringsSep "\n" cfg.ignores + "\n";
        };

        "git/attributes" = mkIf (cfg.attributes != [ ]) {
          text = concatStringsSep "\n" cfg.attributes + "\n";
        };
      };
    }

    {
      programs.git.iniContent = let
        hasSmtp = name: account: account.smtp != null;

        genIdentity = name: account:
          with account;
          nameValuePair "sendemail.${name}" (if account.msmtp.enable then {
            smtpServer = "${pkgs.msmtp}/bin/msmtp";
            envelopeSender = "auto";
            from = address;
          } else
            {
              smtpEncryption = if smtp.tls.enable then
                (if smtp.tls.useStartTls
                || versionOlder config.home.stateVersion "20.09" then
                  "tls"
                else
                  "ssl")
              else
                "";
              smtpSslCertPath =
                mkIf smtp.tls.enable (toString smtp.tls.certificatesFile);
              smtpServer = smtp.host;
              smtpUser = userName;
              from = address;
            } // optionalAttrs (smtp.port != null) {
              smtpServerPort = smtp.port;
            });
      in mapAttrs' genIdentity
      (filterAttrs hasSmtp config.accounts.email.accounts);
    }

    (mkIf (cfg.signing != null) {
      programs.git.iniContent = with cfg.signing;
        let
          formats = [
            {
              format = "openpgp";
              defaultProgram = "${pkgs.gnupg}/bin/gpg2";
            }
            {
              format = "ssh";
              defaultProgram = "${pkgs.openssh}/bin/ssh";
            }
            {
              format = "x509";
              defaultProgram = "${pkgs.gnupg}/bin/gpgsm";
            }
          ];
        in {
          gpg = {
            format = mkIf (signing.format != null) signing.format;
          } // lib.genAttrs formats ({ format, defaultProgram, }: {
            program =
              mkIf (signing.format == f) signing.program or defaultProgram;
          });

          user.signingKey = mkIf (signing.key != null) signing.key;

          commit.gpgSign = mkDefault signing.signByDefault;
          tag.gpgSign = mkDefault signing.signByDefault;
        };
    })

    (mkIf (cfg.hooks != { }) {
      programs.git.iniContent = {
        core.hooksPath = let
          entries =
            mapAttrsToList (name: path: { inherit name path; }) cfg.hooks;
        in toString (pkgs.linkFarm "git-hooks" entries);
      };
    })

    (mkIf (cfg.aliases != { }) { programs.git.iniContent.alias = cfg.aliases; })

    (mkIf (lib.isAttrs cfg.extraConfig) {
      programs.git.iniContent = cfg.extraConfig;
    })

    (mkIf (lib.isString cfg.extraConfig) {
      warnings = [''
        Using programs.git.extraConfig as a string option is
        deprecated and will be removed in the future. Please
        change to using it as an attribute set instead.
      ''];

      xdg.configFile."git/config".text = cfg.extraConfig;
    })

    (mkIf (cfg.includes != [ ]) {
      xdg.configFile."git/config".text = let
        include = i:
          with i;
          if condition != null then {
            includeIf.${condition}.path = "${path}";
          } else {
            include.path = "${path}";
          };
      in mkAfter
      (concatStringsSep "\n" (map gitToIni (map include cfg.includes)));
    })

    (mkIf cfg.lfs.enable {
      home.packages = [ pkgs.git-lfs ];

      programs.git.iniContent.filter.lfs =
        let skipArg = optional cfg.lfs.skipSmudge "--skip";
        in {
          clean = "git-lfs clean -- %f";
          process =
            concatStringsSep " " ([ "git-lfs" "filter-process" ] ++ skipArg);
          required = true;
          smudge = concatStringsSep " "
            ([ "git-lfs" "smudge" ] ++ skipArg ++ [ "--" "%f" ]);
        };
    })

    (mkIf cfg.difftastic.enable {
      home.packages = [ pkgs.difftastic ];

      programs.git.iniContent = let
        difftCommand = concatStringsSep " " [
          "${pkgs.difftastic}/bin/difft"
          "--color ${cfg.difftastic.color}"
          "--background ${cfg.difftastic.background}"
          "--display ${cfg.difftastic.display}"
        ];
      in { diff.external = difftCommand; };
    })

    (let
      deltaPackage = cfg.delta.package;
      deltaCommand = "${deltaPackage}/bin/delta";
    in mkIf cfg.delta.enable {
      home.packages = [ deltaPackage ];

      programs.git.iniContent = {
        core.pager = deltaCommand;
        interactive.diffFilter = "${deltaCommand} --color-only";
        delta = cfg.delta.options;
      };
    })

    (mkIf cfg.diff-so-fancy.enable {
      home.packages = [ pkgs.diff-so-fancy ];

      programs.git.iniContent =
        let dsfCommand = "${pkgs.diff-so-fancy}/bin/diff-so-fancy";
        in {
          core.pager = "${dsfCommand} | ${pkgs.less}/bin/less ${
              escapeShellArgs cfg.diff-so-fancy.pagerOpts
            }";
          interactive.diffFilter = "${dsfCommand} --patch";
          diff-so-fancy = {
            markEmptyLines = cfg.diff-so-fancy.markEmptyLines;
            changeHunkIndicators = cfg.diff-so-fancy.changeHunkIndicators;
            stripLeadingSymbols = cfg.diff-so-fancy.stripLeadingSymbols;
            useUnicodeRuler = cfg.diff-so-fancy.useUnicodeRuler;
            rulerWidth = mkIf (cfg.diff-so-fancy.rulerWidth != null)
              (cfg.diff-so-fancy.rulerWidth);
          };
        };
    })
  ]);
}
