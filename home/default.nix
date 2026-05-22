{ config, pkgs, lib, ... }:
{
  imports = [
    ./packages.nix
    ./packages-darwin.nix
    ./packages-linux.nix
    ./shell/zsh.nix
    ./shell/fish.nix
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
  home.homeDirectory = lib.mkForce (
    if pkgs.stdenv.isDarwin then "/Users/yamer003" else "/home/yamer003"
  );

  home.stateVersion = "24.11";
  programs.home-manager.enable = true;

  # Avoid conflicts when nushell/fish/zsh are also managed by chezmoi
  # Home Manager only enables the programs, config files come from chezmoi
  programs.nushell.configFile.source = lib.mkDefault null;
  programs.nushell.envFile.source = lib.mkDefault null;
}
