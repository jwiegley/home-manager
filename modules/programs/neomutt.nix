{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.programs.neomutt;

  # Accounts for which neomutt is enabled.
  neomuttAccounts =
    filter
      (a: a.neomutt.enable != "none")
      (attrValues config.accounts.email.accounts);

  sidebarModule = types.submodule {
    options = {
      enable = mkEnableOption "sidebar support";

      width = mkOption {
        type = types.int;
        default = 22;
        description = "Width of the sidebar";
      };

      shortPath = mkOption {
        type = types.bool;
        default = true;
        description = ''
          By default sidebar shows the full path of the mailbox, but
          with this enabled only the relative name is shown.
        '';
      };

      format = mkOption {
        type = types.string;
        default = "%B%?F? [%F]?%* %?N?%N/?%S";
        description = ''
          Sidebar format. Check neomutt documentation for details.
        '';
      };
    };
  };

  bindModule = types.submodule {
    options = {
      map = mkOption {
        type = types.enum [
          "alias"
          "attach"
          "browser"
          "compose"
          "editor"
          "generic"
          "index"
          "mix"
          "pager"
          "pgp"
          "postpone"
          "query"
          "smime"
        ];
        default = "index";
        description = "Select the menu to bind the command to.";
      };

      key = mkOption {
        type = types.string;
        example = "<left>";
        description = "The key to bind.";
      };

      action = mkOption {
        type = types.string;
        example = "<enter-command>toggle sidebar_visible<enter><refresh>";
        description = "Specify the action to take.";
      };
    };
  };


  yesno = x: if x then "yes" else "no";
  setOption = n: v: if v == null then "unset ${n}" else "set ${n}=${v}";
  escape = replaceStrings ["%"] ["%25"];

  genCommonFolderHooks = account: with account;
    let
      smtpProto = if smtp.tls.enable then "smtps" else "smtp";
      smtpBaseUrl = "${smtpProto}://${escape userName}@${smtp.host}";
      passCmd = concatStringsSep " " passwordCommand;
    in
      {
        imap_user = null;
        imap_pass = null;
        imap_idle = null;
        tunnel = null;
        from = "'${address}'";
        realname = "'${realName}'";
        spoolfile = "'+${folders.inbox}'";
        record = if folders.sent == null then null else "'+${folders.sent}'";
        postponed = "'+${folders.drafts}'";
        trash = "'+${folders.trash}'";
        smtp_url = "'${smtpBaseUrl}'";
        smtp_pass = "'`${passCmd}`'";
      };

  genMaildirAccountConfig = account: with account;
    let
      folderHook =
        mapAttrsToList setOption (
          genCommonFolderHooks account
          // {
            folder = "'${account.maildir.absPath}'";
          }
        )
        ++ optional (neomutt.extraConfig != "") neomutt.extraConfig;
    in
      ''
        mailboxes ${account.maildir.absPath}/${folders.inbox}
        folder-hook ${account.maildir.absPath}/ " \
          ${concatStringsSep "; \\\n  " folderHook}"
      ''
      + optionalString account.primary ''
        ${concatStringsSep "\n" folderHook}
      '';

  genImapAccountConfig = account: with account;
    let
      imapProto = if imap.tls.enable then "imaps" else "imap";
      imapBaseUrl = "${imapProto}://${userName}@${imap.host}";
      imapBaseUrlEscape = "${imapProto}://${escape userName}@${imap.host}";
      passCmd = concatStringsSep " " passwordCommand;

      folderHook =
        mapAttrsToList setOption (
          genCommonFolderHooks account
          // {
            imap_user="'${userName}'";
            imap_pass="'`${passCmd}`'";
            imap_idle = yesno neomutt.imap.idle;
            folder = "'${imapBaseUrlEscape}'";
          }
        )
        ++ optional (neomutt.extraConfig != "") neomutt.extraConfig;
    in
      ''
        account-hook '${imapBaseUrl}/' " \
          set imap_user='${userName}' \
          set imap_pass='`${passCmd}`' \
          unset tunnel"
        mailboxes '${imapBaseUrlEscape}/${folders.inbox}'
        folder-hook '${imapBaseUrlEscape}/' " \
          ${concatStringsSep "; \\\n  " folderHook}"
      ''
      + optionalString account.primary ''
        ${concatStringsSep "\n" folderHook}
      '';

  genAccountConfig = account: with account;
    if account.neomutt.enable == "imap" && account.imap != null then
      genImapAccountConfig account
    else if account.neomutt.enable == "maildir" && account.maildir != null then
      genMaildirAccountConfig account
    else
      "";
in

{
  options = {
    programs.neomutt = {
      enable = mkEnableOption "the neomutt mail client";

      gpg = mkOption {
        type = types.bool;
        default = false;
        description = "Enable gpg support.";
      };

      sidebar = mkOption {
        type = sidebarModule;
        default = {};
        description = "Options related to the sidebar.";
      };

      binds = mkOption {
        type = types.listOf bindModule;
        default = [];
        description = "List of keybindings.";
      };

      macros = mkOption {
        # I'm sharing the definition of bind, because the fields are pretty
        # much the same
        type = types.listOf bindModule;
        default = [];
        description = "List of macros.";
      };

      sort = mkOption {
        type = types.enum [
          "date"
          "date-received"
          "from"
          "mailbox-order"
          "score"
          "size"
          "spam"
          "subject"
          "threads"
          "to"
        ];
        default = "threads";
        description = "Sorting method on messages.";
      };

      checkStatsInterval = mkOption {
        type = types.nullOr types.int;
        default = null;
        example = 60;
        description = "Enable and set the interval of automatic mail check.";
      };

      editor = mkOption {
        type = types.string;
        default = "$EDITOR";
        example = "${pkgs.nano}/bin/nano";
        description = "Select the editor used for writing mail.";
      };

      theme = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to theme file. Warning this can contain any muttrc
          configuration, including system calls.
        '';
      };

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = "Extra configuration appended to the end.";
      };
    };

    accounts.email.accounts = mkOption {
      options = [
        {
          neomutt = {
            enable = mkOption {
              type = types.enum [ "none" "maildir" "imap" ];
              default = "none";
              description = ''
                Whether to enable this account in NeoMutt and which
                account protocol to use.
              '';
            };

            imap.idle = mkOption {
              type = types.bool;
              default = false;
              description = ''
                If set, neomutt will attempt to use the IDLE extension.
              '';
            };

            mailboxes = mkOption {
              type = types.listOf types.str;
              default = [];
              example = ["github" "Lists/nix" "Lists/haskell-cafe"];
              description = ''
                A list of mailboxes.
              '';
            };

            extraConfig = mkOption {
              type = types.lines;
              default = "";
              example = "color status cyan default";
              description = ''
                Extra lines to add to the folder hook for this account.
              '';
            };
          };
        }
      ];
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      (
        let
          badAccounts =
            filter
              (a: a.neomutt.enable == "maildir" && a.maildir == null)
              neomuttAccounts;
        in
          {
            assertion = badAccounts == [];
            message = "neomutt: Missing maildir configuration for accounts: "
              + concatMapStringsSep ", " (a: a.name) badAccounts;
          }
      )

      (
        let
          badAccounts =
            filter
              (a: a.neomutt.enable == "imap" && a.imap == null)
              neomuttAccounts;
        in
          {
            assertion = badAccounts == [];
            message = "neomutt: Missing IMAP configuration for accounts: "
              + concatMapStringsSep ", " (a: a.name) badAccounts;
          }
      )
    ];

    home.packages = [ pkgs.neomutt ];

    xdg.configFile."neomutt/neomuttrc".text =
      let

        gpgSection = ''
          set crypt_use_gpgme = yes
          set crypt_autosign = yes
          set pgp_use_gpg_agent = yes
        '';

        sidebarSection = ''
          # Sidebar
          set sidebar_visible = yes
          set sidebar_short_path = ${yesno cfg.sidebar.shortPath}
          set sidebar_width = ${toString cfg.sidebar.width}
          set sidebar_format = '${cfg.sidebar.format}'
        '';

        bindSection =
          concatMapStringsSep
            "\n"
            (bind: "bind ${bind.map} ${bind.key} \"${bind.action}\"")
            cfg.binds;

        macroSection =
          concatMapStringsSep
            "\n"
            (bind: "macro ${bind.map} ${bind.key} \"${bind.action}\"")
            cfg.macros;

        accountsSection =
          concatMapStringsSep "\n" genAccountConfig neomuttAccounts;

        mailCheckSection = ''
          set mail_check_stats
          set mail_check_stats_interval = ${toString cfg.checkStatsInterval}
        '';

      in

        # Some defaults are left unconfigurable
        ''
          # Generated by Home Manager.

          set ssl_force_tls = yes
  
          set mbox_type = Maildir
          set sort = "${cfg.sort}"
          set header_cache = "${config.xdg.cacheHome}/neomutt/headers/"
          set message_cachedir = "${config.xdg.cacheHome}/neomutt/messages/"
          set editor = "${cfg.editor}"
  
          ${optionalString cfg.gpg gpgSection}
  
          ${optionalString (cfg.checkStatsInterval != null) mailCheckSection}
  
          set implicit_autoview = yes
  
          alternative_order text/enriched text/plain text
  
          set delete = yes
  
          # Binds and macros
          ${bindSection}
          ${macroSection}
  
          ${optionalString cfg.sidebar.enable sidebarSection}
  
          ${optionalString (cfg.theme != null) "source ${cfg.theme}"}
  
          ${accountsSection}
  
          # Extra configuration
          ${cfg.extraConfig}
        '';
  };
}
