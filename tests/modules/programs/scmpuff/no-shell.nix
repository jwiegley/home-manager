{ pkgs, ... }: {
  config = {
    programs = {
      scmpuff = {
        enable = true;
        enableBashIntegration = false;
        enableZshIntegration = false;
      };
      bash.enable = true;
      zsh.enable = true;
    };

    nmt.script = ''
      assertFileNotRegex home-files/.zshrc '${pkgs.scmpuff} init -s'
      assertFileNotRegex home-files/.bashrc '${pkgs.scmpuff} init -s'
    '';
  };
}
