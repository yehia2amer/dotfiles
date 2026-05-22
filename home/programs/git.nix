# Git — base config. Machine-specific overrides via Chezmoi include.
{ config, pkgs, ... }:
{
  programs.git = {
    enable = true;
    lfs.enable = true;

    settings = {
      user = {
        name = "Yehia Amer";
        email = "yehamer@gmail.com";
      };
      init.defaultBranch = "main";
      pull.rebase = false;
      merge.ff = true;
      core.autocrlf = "input";
      credential.helper = if pkgs.stdenv.isDarwin then "osxkeychain" else "libsecret";
      # Include machine-local overrides managed by Chezmoi
      include.path = "~/.config/git/local.gitconfig";
    };

    ignores = [
      ".DS_Store"
      ".qodo"
      ".dolt/"
      "*.db"
      ".beads-credential-key"
    ];
  };

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
