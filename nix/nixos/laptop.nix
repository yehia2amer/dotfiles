# Placeholder — NixOS laptop configuration
# Fill in hardware-configuration.nix and system settings when setting up the laptop
{ config, pkgs, ... }:
{
  networking.hostName = "nixos-laptop";
  system.stateVersion = "24.11";
}
