{ config, pkgs, ... }:

{
  imports = [ ./fcitx5-stubs.nix ];

  i18n.inputMethod = {
    enabled = "fcitx5";
    fcitx5.addons = with pkgs; [ fcitx5-chinese-addons ];
    fcitx5.waylandFrontend = true;
  };

  nmt.script = ''
    assertFileExists home-files/.config/systemd/user/fcitx5-daemon.service
  '';
}
