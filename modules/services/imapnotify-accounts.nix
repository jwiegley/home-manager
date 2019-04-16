{ lib, ... }:

with lib;

{
  options.imapnotify = {
    enable = mkEnableOption "imapnotify";

    onNotify = mkOption {
      type = with types; either str (attrsOf str);
      default = "";
      example = "\${pkgs.mbsync}/bin/mbsync test-%s";
      description = "Shell commands to run on any event.";
    };

    onNotifyPost = mkOption {
      type = types.either types.str types.attrs;
      default = "";
      example = { mail = "\${pkgs.notmuch}/bin/notmuch new && \${pkgs.libnotify}/bin/notify-send 'New mail arrived'"; };
      description = "Shell commands to run after onNotify event.";
    };

    boxes = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [ "Inbox" "[Gmail]/MyLabel" ];
      description = "IMAP folders to watch.";
    };
  };
}
