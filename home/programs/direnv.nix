# Direnv
{ config, pkgs, ... }:
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    # Nushell integration is handled in Chezmoi-managed nu config.
    enableNushellIntegration = false;
  };
}
