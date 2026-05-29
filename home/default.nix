{ config, pkgs, lib, ... }:
{
  imports = [
    ./packages.nix
    ./packages-darwin.nix
    ./packages-linux.nix
    ./shell/nushell.nix
    ./programs/git.nix
    ./programs/starship.nix
    ./programs/atuin.nix
    ./programs/direnv.nix
    ./programs/bat.nix
    ./programs/fzf.nix
    ./programs/zoxide.nix
    ./programs/gh.nix
  ];


  home.username = "yamer003";
  home.homeDirectory = lib.mkForce "/Users/yamer003";

  home.stateVersion = "24.11";
  programs.home-manager.enable = true;

  # Avoid conflicts when shells are managed by Chezmoi.
  # Fish and zsh are installed as packages; their config files come from Chezmoi.
  programs.nushell.configFile.source = lib.mkDefault null;
  programs.nushell.envFile.source = lib.mkDefault null;
}
