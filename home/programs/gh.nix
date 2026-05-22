# GitHub CLI
{ config, pkgs, ... }:
{
  programs.gh = {
    enable = true;
    settings = {
      version = 1;
      git_protocol = "https";
      prompt = "enabled";
      aliases = {
        co = "pr checkout";
      };
    };
  };
}
