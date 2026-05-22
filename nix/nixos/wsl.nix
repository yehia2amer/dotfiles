# NixOS-WSL configuration
{ config, pkgs, ... }:
{
  wsl.enable = true;
  wsl.defaultUser = "yamer003";
  networking.hostName = "nixos-wsl";
  system.stateVersion = "24.11";
}
