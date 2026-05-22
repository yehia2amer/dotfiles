# Zsh — framework only. Content lives in Chezmoi (~/.config/zsh/local.zsh)
{ config, pkgs, ... }:
{
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    initContent = ''
      # Source Chezmoi-managed local config (aliases, functions, corp env)
      [[ -f ~/.config/zsh/local.zsh ]] && source ~/.config/zsh/local.zsh
    '';
  };
}
