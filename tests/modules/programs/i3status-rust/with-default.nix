{ config, lib, pkgs, ... }:

{
  config = {
    programs.i3status-rust = { enable = true; };

    test.stubs.i3status-rust = { version = "0.30.0"; };

    nmt.script = ''
      assertFileExists home-files/.config/i3status-rust/config-default.toml
      assertFileContent home-files/.config/i3status-rust/config-default.toml \
        ${
          pkgs.writeText "i3status-rust-expected-config" ''
            [[block]]
            block = "disk_space"
            alert = 10
            info_type = "available"
            interval = 60
            path = "/"
            warning = 20

            [[block]]
            block = "memory"
            format = " $icon mem_used_percents "
            format_alt = " $icon $swap_used_percents "

            [[block]]
            block = "cpu"
            interval = 1

            [[block]]
            block = "load"
            format = " $icon $1m "
            interval = 1

            [[block]]
            block = "sound"

            [[block]]
            block = "time"
            format = " $timestamp.datetime(f:'%a %d/%m %R') "
            interval = 60

            [icons]
            icons = "none"

            [theme]
            theme = "plain"
          ''
        }
    '';
  };
}
