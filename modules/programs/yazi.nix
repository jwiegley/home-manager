{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.yazi;
  tomlFormat = pkgs.formats.toml { };

  shellIntegration = ''
    function ya() {
      tmp="$(mktemp -t "yazi-cwd.XXXXX")"
      yazi --cwd-file="$tmp"
      if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        cd -- "$cwd"
      fi
      rm -f -- "$tmp"
    }
  '';
in {
  meta.maintainers = [ maintainers.xyenon ];

  options.programs.yazi = {
    enable = mkEnableOption "yazi";

    package = mkOption {
      type = types.package;
      default = pkgs.yazi;
      defaultText = literalExpression "pkgs.yazi";
      description = "Yazi package to install.";
    };

    enableBashIntegration = mkEnableOption "Bash integration";

    enableZshIntegration = mkEnableOption "Zsh integration";

    keymap = mkOption {
      type = tomlFormat.type;
      default = { };
      example = literalExpression ''
        {
          input.keymap = [
            { exec = "close"; on = [ "<C-q>" ]; }
            { exec = "close --submit"; on = [ "<Enter>" ]; }
            { exec = "escape"; on = [ "<Esc>" ]; }
            { exec = "backspace"; on = [ "<Backspace>" ]; }
          ];
          manager.keymap = [
            { exec = "escape"; on = [ "<Esc>" ]; }
            { exec = "quit"; on = [ "q" ]; }
            { exec = "close"; on = [ "<C-q>" ]; }
          ];
        }
      '';
      description = ''
        Configuration written to
        {file}`$XDG_CONFIG_HOME/yazi/keymap.toml`.

        See <https://github.com/sxyazi/yazi/blob/main/config/docs/keymap.md>
        for the full list of options.
      '';
    };

    settings = mkOption {
      type = tomlFormat.type;
      default = { };
      example = literalExpression ''
        {
          log = {
            enabled = false;
          };
          manager = {
            show_hidden = false;
            sort_by = "modified";
            sort_dir_first = true;
            sort_reverse = true;
          };
        }
      '';
      description = ''
        Configuration written to
        {file}`$XDG_CONFIG_HOME/yazi/yazi.toml`.

        See <https://github.com/sxyazi/yazi/blob/main/config/docs/yazi.md>
        for the full list of options.
      '';
    };

    theme = mkOption {
      type = tomlFormat.type;
      default = { };
      example = literalExpression ''
        {
          filetype = {
            rules = [
              { fg = "#7AD9E5"; mime = "image/*"; }
              { fg = "#F3D398"; mime = "video/*"; }
              { fg = "#F3D398"; mime = "audio/*"; }
              { fg = "#CD9EFC"; mime = "application/x-bzip"; }
            ];
          };
        }
      '';
      description = ''
        Configuration written to
        {file}`$XDG_CONFIG_HOME/yazi/theme.toml`.

        See <https://github.com/sxyazi/yazi/blob/main/config/docs/theme.md>
        for the full list of options
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    programs.bash.initExtra = mkIf cfg.enableBashIntegration shellIntegration;

    programs.zsh.initExtra = mkIf cfg.enableZshIntegration shellIntegration;

    xdg.configFile = {
      "yazi/keymap.toml" = mkIf (cfg.keymap != { }) {
        source = tomlFormat.generate "yazi-keymap" cfg.keymap;
      };
      "yazi/yazi.toml" = mkIf (cfg.settings != { }) {
        source = tomlFormat.generate "yazi-settings" cfg.settings;
      };
      "yazi/theme.toml" = mkIf (cfg.theme != { }) {
        source = tomlFormat.generate "yazi-theme" cfg.theme;
      };
    };
  };
}
