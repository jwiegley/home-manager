{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.programs.opam;

in {
  meta.maintainers = [ ];

  options.programs.opam = {
    enable = mkEnableOption "Opam";

    package = mkOption {
      type = types.package;
      default = pkgs.opam;
      defaultText = literalExpression "pkgs.opam";
      description = "Opam package to install.";
    };

    enableBashIntegration = mkOption {
      default = true;
      type = types.bool;
      description = ''
        Whether to enable Bash integration.
      '';
    };

    enableZshIntegration = mkOption {
      default = true;
      type = types.bool;
      description = ''
        Whether to enable Zsh integration.
      '';
    };

    enableFishIntegration = mkOption {
      default = true;
      type = types.bool;
      description = ''
        Whether to enable Fish integration.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    programs.bash.initExtra = mkIf cfg.enableBashIntegration ''
      eval "$(${cfg.package}/bin/opam env --shell=bash)"
    '';

    programs.zsh.initExtra = mkIf cfg.enableZshIntegration ''
      eval "$(${cfg.package}/bin/opam env --shell=zsh)"
    '';

    programs.fish.shellInit = mkIf cfg.enableFishIntegration ''
      eval (${cfg.package}/bin/opam env --shell=fish)
    '';
  };
}
