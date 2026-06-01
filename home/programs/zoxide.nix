# Zoxide — smart cd
{ config, pkgs, ... }:
{
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    enableFishIntegration = true;
    # Nushell integration is handled in Chezmoi-managed nu config.
    enableNushellIntegration = false;
  };
}
