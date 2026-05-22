# Linux-only packages
{ pkgs, lib, ... }:
{
  home.packages = lib.optionals pkgs.stdenv.isLinux (with pkgs; [
    ntfs3g
    pinentry-gtk2
    e2tools
    weave-gitops
    xdg-utils
    xclip
  ]);
}
