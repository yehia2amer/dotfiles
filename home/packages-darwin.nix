# macOS-only packages
{ pkgs, lib, ... }:
{
  home.packages = lib.optionals pkgs.stdenv.isDarwin (with pkgs; [
    dmg2img
    libimobiledevice
    pinentry_mac
    xcodegen
  ]);
}
