# NixOS-WSL configuration
{ config, pkgs, lib, ... }:
{
  # ── WSL ──
  wsl.enable = true;
  wsl.defaultUser = "yamer003";
  wsl.wslConf.network.generateResolvConf = false;

  # ── Networking ──
  networking.hostName = "nixos-wsl";
  networking.proxy = {
    httpProxy = "http://127.0.0.1:3128";
    httpsProxy = "http://127.0.0.1:3128";
    noProxy = "localhost,127.0.0.1,::1,.db.de,.rz.db.de";
  };

  # Node.js/undici needs uppercase proxy vars + native proxy support
  environment.variables = {
    HTTP_PROXY = "http://127.0.0.1:3128";
    HTTPS_PROXY = "http://127.0.0.1:3128";
    NO_PROXY = "localhost,127.0.0.1,::1,.db.de,.rz.db.de";
    NODE_USE_ENV_PROXY = "1";
  };

  # ── Nix settings ──
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "yamer003" ];
  };

  # Allow unfree packages (vault-bin, etc.)
  nixpkgs.config.allowUnfree = true;

  # ── User account ──
  users.users.yamer003 = {
    isNormalUser = true;
    home = "/home/yamer003";
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ];
  };

  # Enable zsh system-wide (required for user shell)
  programs.zsh.enable = true;

  # Allow wheel group passwordless sudo (convenient for WSL)
  security.sudo.wheelNeedsPassword = false;

  # ── System packages (minimal — most come from Home Manager) ──
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    libsecret  # provides secret-tool for chezmoi templates
    gnome-keyring
    dbus
  ];

  # Enable gnome-keyring for secret-tool (headless)
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;

  # Auto-unlock gnome-keyring and set required env vars for secret-tool in WSL
  environment.sessionVariables = {
    XDG_RUNTIME_DIR = "/run/user/1000";
    DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus";
  };

  # Auto-unlock keyring with empty password on login
  system.userActivationScripts.unlockKeyring = ''
    echo "" | ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --unlock --components=secrets 2>/dev/null || true
  '';

  # ── DNS (uses Ubuntu WSL's dnsmasq via shared network namespace) ──
  networking.resolvconf.enable = false;
  environment.etc."resolv.conf".text = ''
    nameserver 127.0.0.1
  '';

  system.stateVersion = "24.11";
}
