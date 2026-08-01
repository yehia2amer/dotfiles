{ pkgs, lib, ... }:
let
  primaryUser = "yamer003";
  homeDirectory = "/Users/${primaryUser}";

  # Corporate MITM CA bundle for a work-managed machine. NOT stored in this repo
  # (contains corp certs). It's a merged bundle (public roots + corporate
  # root/issuing) generated on-machine by scripts/setup-work-ca-bundle.sh.
  # Referenced by absolute path as a string, so the cert is NOT copied into the
  # Nix store or committed. Only the MacBookProM3 (work Mac) target uses this
  # module; NixOS hosts use separate configs. See docs/work-machine-bootstrap.md.
  workCaBundle = "/etc/nix/ca-bundle-work.crt";
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
  imports = [ ./homebrew.nix ];

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
  nix.settings = {
    experimental-features = "nix-command flakes";
    # Trust public roots + corporate CA (works VPN on/off). Written into
    # /etc/nix/nix.conf; read by the nix-daemon for store downloads.
    ssl-cert-file = workCaBundle;
  };

  # Client-side TLS (flake fetching, nix run) — override the installer default
  # NIX_SSL_CERT_FILE so `nix` clients also trust the corporate CA.
  environment.variables.NIX_SSL_CERT_FILE = workCaBundle;

  # Allow specific unfree packages
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "android-sdk-ndk"
      "android-sdk-platform-tools"
      "ndk"
      "platform-tools"
      "claude-code"
      "github-copilot-cli"
      "vault-bin"
      "bws"  # Bitwarden Secrets Manager CLI (see docs/varlock-bitwarden-secrets.md)
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
