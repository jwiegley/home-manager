{ config, lib, ... }:

with lib;

{
  config = {
    programs.git = mkMerge [
      {
        enable = true;
        aliases = {
          a1 = "foo";
          a2 = "bar";
        };
        extraConfig = {
          extra = {
            name = "value";
          };
        };
        ignores = [ "*~" "*.swp" ];
        includes = [
          { path = "~/path/to/config.inc"; }
          {
            path = "~/path/to/conditional.inc";
            condition = "gitdir:~/src/dir";
          }
        ];
        signing = {
          gpgPath = "path-to-gpg";
          key = "00112233445566778899AABBCCDDEEFF";
          signByDefault = true;
        };
        userEmail = "user@example.org";
        userName = "John Doe";
        lfs.enable = true;
      }

      {
        aliases.a2 = mkForce "baz";
        extraConfig.extra.boolean = true;
        extraConfig.extra.integer = 38;
      }
    ];

    nmt.script = ''
      assertFileExists home-files/.config/git/config
      assertFileContent home-files/.config/git/config ${./git-expected.conf}
    '';
  };
}
