{ config, lib, pkgs, ... }:

with lib;

{
  config = {
    programs.rcm = {
      enable = true;
      settings = {
        UNDOTTED = [ ];
        EXCLUDES = [ ".git" ".gitignore" ];
      };
    };

    test.stubs.rcm = { };

    nmt.script = ''
      assertFileExists home-files/.rcrc
      assertFileRegex home-files/.rcrc 'EXCLUDES=\".git .gitignore\"'
      assertFileRegex home-files/.rcrc 'UNDOTTED=\"\"'
    '';
  };
}
