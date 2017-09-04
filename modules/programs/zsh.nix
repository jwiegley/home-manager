{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.programs.zsh;

  historyModule = types.submodule {
    options = {
      size = mkOption {
        type = types.int;
        default = 10000;
        description = "Number of history lines to keep.";
      };

      path = mkOption {
        type = types.str;
        default = "$HOME/.zsh_history";
        description = "History file location";
      };

      ignoreDups = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Do not enter command lines into the history list
          if they are duplicates of the previous event.
        '';
      };

      share = mkOption {
        type = types.bool;
        default = true;
        description = "Share command history between zsh sessions.";
      };
    };
  };

  pluginModule = types.submodule ({ config, ... }: {
    options = {
      src = mkOption {
        type = types.path;
        description = "Path to the plugin folder. Will be added to <envar>fpath</envar> and <envar>PATH</envar>.";
      };

      name = mkOption {
        type = types.str;
        description = "The name of the plugin. Use <option>file</option> instead if the script name does not follow convention.";
      };

      file = mkOption {
        type = types.str;
        description = "The plugin script to source.";
      };
    };

    config.file = mkDefault "${config.name}.plugin.zsh";
  });

in

{
  options = {
    programs.zsh = {
      enable = mkEnableOption "Z shell (Zsh)";

      shellAliases = mkOption {
        default = {};
        example = { ll = "ls -l"; ".." = "cd .."; };
        description = ''
          An attribute set that maps aliases (the top level attribute names in
          this option) to command strings or directly to build outputs.
        '';
        type = types.attrs;
      };

      enableCompletion = mkOption {
        default = true;
        description = "Enable zsh completion.";
        type = types.bool;
      };

      enableAutosuggestions = mkOption {
        default = false;
        description = "Enable zsh autosuggestions";
      };

      history = mkOption {
        type = historyModule;
        default = {};
        description = "Options related to commands history configuration.";
      };

      initExtra = mkOption {
        default = "";
        type = types.lines;
        description = "Extra commands that should be added to <filename>.zshrc</filename>.";
      };

      plugins = mkOption {
        type = types.listOf pluginModule;
        default = [];
        example = literalExample ''
          [
            {
              # will source zsh-autosuggestions.plugin.zsh
              name = "zsh-autosuggestions";
              src = pkgs.fetchFromGitHub {
                owner = "zsh-users";
                repo = "zsh-autosuggestions";
                rev = "v0.4.0";
                sha256 = "0z6i9wjjklb4lvr7zjhbphibsyx51psv50gm07mbb0kj9058j6kc";
              };
            }
            {
              file = "init.sh";
              src = pkgs.fetchFromGitHub {
                owner = "b4b4r07";
                repo = "enhancd";
                rev = "v2.2.1";
                sha256 = "0iqa9j09fwm6nj5rpip87x3hnvbbz9w9ajgm6wkrd5fls8fn8i5g";
              };
            }
          ]
        '';
        description = "Plugins to source in <filename>.zshrc</filename>.";
      };
    };
  };

  config = (
    let
      aliasesStr = concatStringsSep "\n" (
        mapAttrsToList (k: v: "alias ${k}='${v}'") cfg.shellAliases
      );

      export = n: v: "export ${n}=\"${toString v}\"";

      envVarsStr = concatStringsSep "\n" (
        mapAttrsToList export config.home.sessionVariables
      );
    in mkIf cfg.enable {
      home.packages = [ pkgs.zsh ]
        ++ optional cfg.enableCompletion pkgs.nix-zsh-completions;

      home.file.".zshenv".text = ''
        ${optionalString (config.home.sessionVariableSetter == "zsh")
          envVarsStr}
      '';

      home.file.".zshrc".text = ''
        ${export "HISTSIZE" cfg.history.size}
        ${export "HISTFILE" cfg.history.path}

        setopt HIST_FCNTL_LOCK
        ${if cfg.history.ignoreDups then "setopt" else "unsetopt"} HIST_IGNORE_DUPS
        ${if cfg.history.share then "setopt" else "unsetopt"} SHARE_HISTORY

        HELPDIR="${pkgs.zsh}/share/zsh/$ZSH_VERSION/help"

        ${concatStrings (map (plugin: ''
          path+="${plugin.src}"
          fpath+="${plugin.src}"
        '') cfg.plugins)}

        ${optionalString cfg.enableCompletion "autoload -U compinit && compinit -C"}
        ${optionalString (cfg.enableAutosuggestions)
          "source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
        }

        ${concatStrings (map (plugin: ''
          source "${plugin.src}/${plugin.file}"
        '') cfg.plugins)}

        ${aliasesStr}

        ${cfg.initExtra}
      '';

      programs.zsh = mkIf (builtins.length cfg.plugins > 0) {
        enableCompletion = mkDefault true;
      };
    }
  );
}
