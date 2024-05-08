{ ... }:

{
  services.blanket = {
    enable = true;
  };

  test.stubs.blanket = { };

  nmt.script = ''
    clientServiceFile=home-files/.config/systemd/user/blanket.service

    assertFileExists $clientServiceFile
  '';
}
