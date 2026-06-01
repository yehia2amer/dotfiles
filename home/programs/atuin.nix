# Atuin — shell history
{ config, pkgs, ... }:
{
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    enableFishIntegration = true;
    # Nushell integration is handled in Chezmoi-managed nu config.
    enableNushellIntegration = false;
  };
}
