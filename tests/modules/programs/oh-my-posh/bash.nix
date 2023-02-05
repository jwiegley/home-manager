{ ... }:

{
  programs = {
    bash.enable = true;

    oh-my-posh = {
      enable = true;
      useTheme = "jandedobbeleer";
    };
  };

  test.stubs.oh-my-posh = { };

  nmt.script = ''
    assertFileExists home-files/.bashrc
    assertFileContains \
      home-files/.bashrc \
      '/bin/oh-my-posh init bash --config'
  '';
}
