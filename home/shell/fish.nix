# Fish — enable only. Config managed by Chezmoi.
{ config, pkgs, lib, ... }:
{
  programs.fish = {
    enable = true;
    # Source chezmoi-managed local config (like zsh does with local.zsh)
    interactiveShellInit = ''
      if test -f ~/.config/fish/local.fish
        source ~/.config/fish/local.fish
      end
    '';
  };
}
