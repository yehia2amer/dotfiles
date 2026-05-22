# Nushell — enable only. config.nu + env.nu managed by Chezmoi.
{ config, pkgs, ... }:
{
  programs.nushell.enable = true;
}
