{ pkgs, lib, ... }:
{
  # System packages (minimal — most go in Home Manager)
  environment.systemPackages = with pkgs; [
    vim
    git
  ];

  # Primary user (required for system.defaults)
  system.primaryUser = "yamer003";

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
      AppleInterfaceStyleSwitchesAutomatically = true;
    };
    dock = {
      autohide = true;
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
