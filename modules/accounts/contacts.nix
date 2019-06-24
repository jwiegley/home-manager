{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.accounts.contact;

  contactOpts = { name, config, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        readOnly = true;
        description = ''
          Unique identifier of the contact. This is set to the
          attribute name of the contact configuration.
        '';
      };

      path = mkOption {
        type = types.str;
        default = "${cfg.basePath}/${name}";
        description = "The path of the storage.";
      };
    };

    config = mkMerge [
      {
        name = name;
        khal.type = mkOptionDefault "birthdays";
      }
    ];
  };

in

{
  options.accounts.contact = {
    basePath = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.contacts/";
      defaultText = "$HOME/.contacts";
      description = ''
        The base directory in which to save contacts.
      '';
    };

    accounts = mkOption {
      type = types.attrsOf (types.submodule [
        contactOpts
        (import ../programs/vdirsyncer-accounts.nix)
        (import ../programs/khal-accounts.nix)
      ]);
      default = {};
      description = "List of contacts.";
    };
  };
  config = mkIf (cfg.accounts != {}) {
  };
}
