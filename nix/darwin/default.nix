{ pkgs, lib, ... }:
let
  primaryUser = "yamer003";
  homeDirectory = "/Users/${primaryUser}";
  userBinPath = [
    "/etc/profiles/per-user/${primaryUser}/bin"
    "${homeDirectory}/.nix-profile/bin"
    "${homeDirectory}/.local/bin"
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "/Applications/Postgres.app/Contents/Versions/latest/bin"
    "${homeDirectory}/.bun/bin"
    "${homeDirectory}/.rd/bin"
    "${homeDirectory}/.atuin/bin"
    "/usr/local/share/dotnet"
  ];
  baseBinPath = userBinPath ++ [
    "/run/current-system/sw/bin"
    "/nix/var/nix/profiles/default/bin"
    "/usr/local/bin"
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
  ];
in
{
  # System packages (minimal — most go in Home Manager)
  environment.systemPackages = with pkgs; [
    vim
    git
  ];

  environment.systemPath = userBinPath;

  launchd.user.envVariables.PATH = baseBinPath;

  # Primary user (required for system.defaults)
  system.primaryUser = primaryUser;

  # Nix settings
  nix.settings.experimental-features = "nix-command flakes";

  # Allow specific unfree packages
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "vault-bin"
    ];

  # macOS system defaults
  system.defaults = {
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      AppleInterfaceStyle = "Dark";
      AppleInterfaceStyleSwitchesAutomatically = false;
    };
    dock = {
      autohide = false;
      show-recents = false;
    };
    finder = {
      AppleShowAllExtensions = true;
      FXPreferredViewStyle = "clmv";
    };
  };

  # Platform
  nixpkgs.hostPlatform = "aarch64-darwin";

  # State version
  system.stateVersion = 5;
}
