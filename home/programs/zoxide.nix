# Zoxide — smart cd
{ config, pkgs, ... }:
{
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    enableFishIntegration = true;
    enableNushellIntegration = true;
  };
}
