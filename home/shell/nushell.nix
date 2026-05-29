# Nushell — enable only. config.nu + env.nu managed by Chezmoi.
{ config, pkgs, lib, ... }:
{
  programs.nushell.enable = true;
  # Force-suppress HM-generated config files so chezmoi can own them
  programs.nushell.configFile.source = lib.mkForce null;
  programs.nushell.envFile.source = lib.mkForce null;
}
