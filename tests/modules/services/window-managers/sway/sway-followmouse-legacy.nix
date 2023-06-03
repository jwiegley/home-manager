{ config, pkgs, ... }:

{
  imports = [ ./sway-stubs.nix ];

  wayland.windowManager.sway = {
    enable = true;

    config = {
      focus.followMouse = false;
      menu = "${pkgs.dmenu}/bin/dmenu_run";
      bars = [ ];
    };
  };

  nmt.script = ''
    assertFileExists home-files/.config/sway/config
    assertFileContent $(normalizeStorePaths home-files/.config/sway/config) \
      ${./sway-followmouse-legacy-expected.conf}
  '';
}
