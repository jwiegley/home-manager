{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.programs.readline;

in

{
  options.programs.readline = {
    enable = mkEnableOption "readline";

    bindings = mkOption {
      default = {};
      type = types.attrsOf types.str;
      example = { "\C-h" = "backward-kill-word"; };
      description = "Readline bindings.";
    };

    includeSystemConfig = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to include the system-wide configuration.";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Configuration lines appended unchanged to the end of the
        <filename>~/.inputrc</filename> file.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.file.".inputrc".text =
      let
        includeSystemStr = if cfg.includeSystem then "$include /etc/inputrc" else "";
        bindingsStr = concatStringsSep "\n" (
          mapAttrsToList (k: v: "\"${k}\": ${v}") cfg.bindings
        );
      in
        ''
          ${includeSystemStr}
          ${bindingsStr}
          ${cfg.extraConfig}
        '';
  };
}
