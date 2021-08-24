{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.programs.kitty;

  eitherStrBoolInt = with types; either str (either bool int);

  optionalPackage = opt:
    optional (opt != null && opt.package != null) opt.package;

  toKittyConfig = generators.toKeyValue {
    mkKeyValue = key: value:
      let
        value' = if isBool value then
          (if value then "yes" else "no")
        else
          toString value;
      in "${key} ${value'}";
  };

  toKittyKeybindings = generators.toKeyValue {
    mkKeyValue = key: command: "map ${key} ${command}";
  };

  toKittyEnv =
    generators.toKeyValue { mkKeyValue = name: value: "env ${name}=${value}"; };

in {
  options.programs.kitty = {
    enable = mkEnableOption "Kitty terminal emulator";

    darwinLaunchOptions = mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      description = "Command-line options to use when launched by Mac OS GUI";
      example = literalExample ''
        [
          "--single-instance"
          "--directory=/tmp/my-dir"
          "--listen-on=unix:/tmp/my-socket"
        ]
      '';
    };

    settings = mkOption {
      type = types.attrsOf eitherStrBoolInt;
      default = { };
      example = literalExample ''
        {
          scrollback_lines = 10000;
          enable_audio_bell = false;
          update_check_interval = 0;
        }
      '';
      description = ''
        Configuration written to
        <filename>~/.config/kitty/kitty.conf</filename>. See
        <link xlink:href="https://sw.kovidgoyal.net/kitty/conf.html" />
        for the documentation.
      '';
    };

    font = mkOption {
      type = types.nullOr hm.types.fontType;
      default = null;
      description = "The font to use.";
    };

    keybindings = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Mapping of keybindings to actions.";
      example = literalExample ''
        {
          "ctrl+c" = "copy_or_interrupt";
          "ctrl+f>2" = "set_font_size 20";
        }
      '';
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Environment variables to set or override.";
      example = literalExample ''
        {
          "LS_COLORS" = "1";
        }
      '';
    };

    extraConfig = mkOption {
      default = "";
      type = types.lines;
      description = "Additional configuration to add.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [{
      assertion = (cfg.darwinLaunchOptions != null)
        -> pkgs.stdenv.hostPlatform.isDarwin;
      message = ''
        kitty: darwinLaunchOptions is only available on darwin.
      '';
    }];

    home.packages = [ pkgs.kitty ] ++ optionalPackage cfg.font;

    xdg.configFile."kitty/kitty.conf".text = ''
      # Generated by Home Manager.
      # See https://sw.kovidgoyal.net/kitty/conf.html

      ${optionalString (cfg.font != null) ''
        font_family ${cfg.font.name}
        ${optionalString (cfg.font.size != null)
        "font_size ${toString cfg.font.size}"}
      ''}

      ${toKittyConfig cfg.settings}

      ${toKittyKeybindings cfg.keybindings}

      ${toKittyEnv cfg.environment}

      ${cfg.extraConfig}
    '';

    xdg.configFile."kitty/macos-launch-services-cmdline" =
      mkIf (!(isNull cfg.darwinLaunchOptions)) {
        text = concatStringsSep " " cfg.darwinLaunchOptions;
      };
  };
}
