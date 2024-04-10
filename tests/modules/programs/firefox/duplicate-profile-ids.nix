{ config, lib, ... }:

{
  imports = [ ./setup-firefox-mock-overlay.nix ];

  config = lib.mkIf config.test.enableBig {
    test.asserts.assertions.expected = [''
      Must not have Firefox profiles with duplicate IDs but
        - ID 1 is used by first, second''];

    programs.firefox = {
      enable = true;

      profiles = {
        first = {
          isDefault = true;
          id = 1;
        };
        second = { id = 1; };
      };
    };
  };
}
