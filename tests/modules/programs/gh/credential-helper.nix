{ config, lib, pkgs, ... }:

{
  programs.gh = {
    enable = true;
    enableGitCredentialHelper = true;
    extraGitCredentialHelperHosts = [ "https://github.example.com" ];
  };

  programs.git.enable = true;

  test.stubs.gh = { };

  nmt.script = ''
    assertFileExists home-files/.config/git/config
    assertFileContent home-files/.config/git/config \
      ${./credential-helper.git.conf}
  '';
}
