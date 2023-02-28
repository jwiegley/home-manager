{ config, lib, pkgs, ... }:

with lib;

{
  meta.maintainers = [ hm.maintainers.kalhauge ];

  options.programs.exa = {
    enable =
      mkEnableOption "exa, a modern replacement for <command>ls</command>";

    enableAliases = mkEnableOption "recommended exa aliases";

    extraOptions = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "--group-directories-first" "--header" ];
      description = ''
        Extra command line options passed to exa.
      '';
    };

    icons = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Display icons next to file names (<option>--icons</option> argument).
      '';
    };

    git = mkOption {
      type = types.bool;
      default = false;
      description = ''
        List each file's Git status if tracked or ignored (<option>--git</option> argument).
      '';
    };

    package = mkPackageOption pkgs "exa" { };
  };

  config = let
    cfg = config.programs.exa;

    cmd = escapeShellArgs ([ "exa" ] ++ optional cfg.icons "--icons"
      ++ optional cfg.git "--git" ++ cfg.extraOptions);

    aliases = {
      # Use `command` instead of hardcoding the path to exa so that aliases don't
      # go stale after a system update.
      exa = "command ${cmd}";
      ls = "exa";
      ll = "exa -l";
      la = "exa -a";
      lt = "exa --tree";
      lla = "exa -la";
    };
  in mkIf cfg.enable {
    home.packages = [ cfg.package ];

    programs.bash.shellAliases = mkIf cfg.enableAliases aliases;

    programs.zsh.shellAliases = mkIf cfg.enableAliases aliases;

    programs.fish.shellAliases = mkIf cfg.enableAliases aliases;

    # ion doesn't support the standard `command` built-in. Or recursive alias expansion.
    programs.ion.shellAliases =
      mkIf cfg.enableAliases (aliases // { exa = cmd; });
  };
}
