# Fzf — fuzzy finder
{ config, pkgs, ... }:
{
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    enableFishIntegration = true;
  };
}
