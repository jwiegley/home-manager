{ config, lib, pkgs, ... }:

with lib;

{
  config = {
    programs.neovim = {
      enable = true;
      vimAlias = true;
      withNodeJs = false;
      withPython3 = true;
      withRuby = false;

      extraPython3Packages = (ps: with ps; [ jedi pynvim ]);

      # plugins without associated config should not trigger the creation of init.vim
      plugins = with pkgs.vimPlugins; [ fugitive ({ plugin = vim-sensible; }) ];
    };
    nmt.script = ''
      vimrc="home-files/.config/nvim/init.vim"
      assertPathNotExists "$vimrc"
    '';
  };
}
