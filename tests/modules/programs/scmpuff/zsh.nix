{ pkgs, ... }: {
  config = {
    programs = {
      scmpuff.enable = true;
      zsh.enable = true;
    };

    nmt.script = ''
      assertFileExists home-files/.zshrc
      assertFileContains \
        home-files/.zshrc \
        'eval "$(${pkgs.scmpuff}/bin/scmpuff init -s)"'
    '';
  };
}
