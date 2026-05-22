# Bat — cat replacement with syntax highlighting
{ config, pkgs, ... }:
{
  programs.bat = {
    enable = true;
    config = {
      theme = "TwoDark";
    };
  };
}
