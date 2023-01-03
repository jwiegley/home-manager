{ config, options, lib, pkgs, ... }:

with lib;

let

  cfg = config.home.pointerCursor;

  pointerCursorModule = types.submodule {
    options = {
      package = mkOption {
        type = types.package;
        example = literalExpression "pkgs.vanilla-dmz";
        description = "Package providing the cursor theme.";
      };

      name = mkOption {
        type = types.str;
        example = "Vanilla-DMZ";
        description = "The cursor name within the package.";
      };

      size = mkOption {
        type = types.int;
        default = 32;
        example = 64;
        description = "The cursor size.";
      };

      x11 = {
        defaultCursor = mkOption {
          type = types.str;
          default = "left_ptr";
          example = "X_cursor";
          description = "The default cursor file to use within the package.";
        };
      };
    };
  };

  cursorPath = "${cfg.package}/share/icons/${escapeShellArg cfg.name}/cursors/${
      escapeShellArg cfg.x11.defaultCursor
    }";

in {
  meta.maintainers = [ maintainers.polykernel maintainers.league ];

  imports = [
    (mkAliasOptionModule [ "xsession" "pointerCursor" "package" ] [
      "home"
      "pointerCursor"
      "package"
    ])
    (mkAliasOptionModule [ "xsession" "pointerCursor" "name" ] [
      "home"
      "pointerCursor"
      "name"
    ])
    (mkAliasOptionModule [ "xsession" "pointerCursor" "size" ] [
      "home"
      "pointerCursor"
      "size"
    ])
    (mkAliasOptionModule [ "xsession" "pointerCursor" "defaultCursor" ] [
      "home"
      "pointerCursor"
      "x11"
      "defaultCursor"
    ])
  ];

  options = {
    home.pointerCursor = mkOption {
      type = types.nullOr pointerCursorModule;
      default = null;
      description = ''
        Cursor configuration. Set to <literal>null</literal> to disable.
        </para><para>
        Top-level options declared under this submodule are backend indepedent
        options. Options declared under namespaces such as <literal>x11</literal>
        are backend specific options. By default, only backend independent cursor
        configurations are generated.
        </para><para>
        X11 specific cursor configurations are enabled when the X session is enabled via
        <xref linkend="opt-xsession.enable"/>.
        GTK specific cursor configurations are enabled when GTK configurations are enabled via
        <xref linkend="opt-gtk.enable"/>.
      '';
    };
  };

  config = mkIf (cfg != null) (mkMerge [
    {
      assertions = [
        (hm.assertions.assertPlatform "home.pointerCursor" pkgs platforms.linux)
      ];

      home.packages = [ cfg.package ];

      # Set name in icons theme, for compatibility with AwesomeWM etc. See:
      # https://github.com/nix-community/home-manager/issues/2081
      # https://wiki.archlinux.org/title/Cursor_themes#XDG_specification
      home.file.".icons/default/index.theme".text = ''
        [icon theme]
        Name=Default
        Comment=Default Cursor Theme
        Inherits=${cfg.name}
      '';

      # Set directory to look for cursors in, needed for some applications
      # that are unable to find cursors otherwise. See:
      # https://github.com/nix-community/home-manager/issues/2812
      # https://wiki.archlinux.org/title/Cursor_themes#Environment_variable
      home.sessionVariables = {
        XCURSOR_PATH = "$XCURSOR_PATH\${XCURSOR_PATH:+:}"
          + "${config.home.profileDirectory}/share/icons";
      };
    }

    (mkIf config.xsession.enable {
      xsession.initExtra = ''
        ${pkgs.xorg.xsetroot}/bin/xsetroot -xcf ${cursorPath} ${
          toString cfg.size
        }
      '';

      xresources.properties = {
        "Xcursor.theme" = cfg.name;
        "Xcursor.size" = cfg.size;
      };
    })

    (mkIf config.gtk.enable {
      gtk.cursorTheme = mkDefault { inherit (cfg) package name size; };
    })
  ]);
}
