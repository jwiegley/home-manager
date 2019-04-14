{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.services.imapnotify;

  imapnotifyAccounts =
    filter (a: a.imapnotify.enable) (attrValues config.accounts.email.accounts);

  genAccountUnit = account: {
    name = "imapnotify@${account.address}";
    value = {
      Unit = {
        Description = "Execute scripts on IMAP mailbox changes (new/deleted/updated messages) using IDLE for %i";
        PartOf = [ "network-online.target" ];
      };

      Service = {
        ExecStart = "${pkgs.imapnotify}/bin/imapnotify -c %E/imap_inotify/%i-config.js";
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };

  genAccountConfig = account: {
    name = "imap_inotify/${account.address}-config.js";
    value = {
      text =
        let
          port = if account.imap.port != null
                   then account.imap.port
                   else if account.imap.tls.enable then 993 else 143;
        in ''
          var child_process = require('child_process');

          function getStdout(cmd) {
              var stdout = child_process.execSync(cmd);
              return stdout.toString().trim();
          }

          exports.host = "${account.imap.host}"
          exports.port = ${toString port};
          exports.tls = ${if account.imap.tls.enable then "true" else "false"};
          exports.username = "${account.userName}";
          exports.password = getStdout("${toString account.passwordCommand}");
          exports.onNotify = ${builtins.toJSON account.imapnotify.onNotify};
          exports.onNotifyPost = ${builtins.toJSON account.imapnotify.onNotifyPost};
          exports.boxes = ${builtins.toJSON account.imapnotify.boxes};
        '';
    };
  };

in

{
  meta.maintainers = [ maintainers.nickhu ];

  options = {
    services.imapnotify = {
      enable = mkEnableOption "imapnotify";
    };
  };

  config = mkIf cfg.enable {
      assertions =
        let
          checkAccounts = pred: msg:
          let
            badAccounts = filter pred imapnotifyAccounts;
          in {
            assertion = badAccounts == [];
            message = "imapnotify: ${msg} for accounts: "
              + concatMapStringsSep ", " (a: a.name) badAccounts;
          };
        in
          [
            (checkAccounts (a: a.maildir == null) "Missing maildir configuration")
            (checkAccounts (a: a.imap == null) "Missing IMAP configuration")
            (checkAccounts (a: a.passwordCommand == null) "Missing passwordCommand")
            (checkAccounts (a: a.userName == null) "Missing username")
          ];

      systemd.user.services =
        listToAttrs (map genAccountUnit imapnotifyAccounts);

      xdg.configFile =
        listToAttrs (map genAccountConfig imapnotifyAccounts);
  };
}
