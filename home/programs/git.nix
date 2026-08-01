# Git — base config. Machine-specific overrides via Chezmoi include.
{ config, pkgs, ... }:
{
  programs.git = {
    enable = true;
    lfs.enable = true;

    settings = {
      user = {
        name = "Yehia Amer";
        email = "yehamer@gmail.com";  # personal default; overridden under ~/src/work/
        useConfigOnly = true;          # never fabricate identity from username@host
      };
      init.defaultBranch = "main";
      pull.rebase = false;
      merge.ff = true;
      core.autocrlf = "input";
      core.excludesfile = "~/.gitignore";
      credential.helper = if pkgs.stdenv.isDarwin then "osxkeychain" else "libsecret";
      # Include machine-local overrides managed by Chezmoi
      include.path = "~/.config/git/local.gitconfig";
    };
  };

  # Location-based identity (Phase 3). Uses programs.git.includes (not settings)
  # because HM renders these with lib.mkAfter — i.e. AFTER the base [user] block —
  # so a matching gitdir include correctly overrides the personal default.
  programs.git.includes = [
    { condition = "gitdir:~/src/personal/"; path = "~/.gitconfig-personal"; }
    { condition = "gitdir:~/src/work/"; path = "~/.gitconfig-work"; }
  ];

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      side-by-side = true;
      line-numbers = true;
    };
  };
}
