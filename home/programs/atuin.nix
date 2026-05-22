# Atuin — shell history
{ config, pkgs, ... }:
{
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    enableFishIntegration = true;
    enableNushellIntegration = true;
  };
}
