# Fzf — fuzzy finder
{ config, pkgs, ... }:
{
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    enableFishIntegration = true;
    # Atuin owns Ctrl-R in both shells.
    historyWidget.command = "";
  };
}
