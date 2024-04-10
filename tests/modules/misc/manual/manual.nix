{ ... }:

{
  config = {
    manual = {
      html.enable = true;
      manpages.enable = true;
      json.enable = true;
    };

    nmt.script = ''
      assertFileExists home-path/share/doc/home-manager/index.html
      assertFileExists home-path/share/doc/home-manager/options.html
      assertFileExists home-path/share/doc/home-manager/options.json
      assertFileExists home-path/share/man/man1/home-manager.1
      assertFileExists home-path/share/man/man5/home-configuration.nix.5
    '';
  };
}
