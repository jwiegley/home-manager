{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.programs.tiny;
  format = pkgs.formats.yaml { };
in {
  meta.maintaners = [ maintainers.kmaasrud ];

  options = {
    programs.tiny = {
      enable = mkEnableOption "tiny";

      package = mkOption {
        type = types.package;
        default = pkgs.tiny;
        defaultText = literalExpression "pkgs.tiny";
        description = "The tiny package to install.";
      };

      settings = mkOption {
        type = format.type;
        default = { };
        example = literalExpression ''
          {
            servers = [
              { 
                addr = "irc.libera.chat"; 
                port = 6697; 
                tls = true;
                realname = "John Doe";
                nicks = [ "tinyuser" ];
              }
            ];
            defaults = {
              nicks = [ "tinyuser" ];
              realname = "John Doe";
              join = [];
              tls = true;
            };
          };
        '';
        description = ''
          Configuration written to
          <filename>$XDG_CONFIG_HOME/tiny/config.yml</filename>. See
          <link xlink:href="https://github.com/osa1/tiny/blob/master/crates/tiny/config.yml"/>
          for the default configuration.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile."tiny/config.yml" = mkIf (cfg.settings != { }) {
      source = format.generate "tiny-config" cfg.settings;
    };
  };
}
