# NixOS-WSL configuration — fully independent (own proxy + DNS)
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

  # ── cntlm (NTLM authenticating proxy — makes this system independent) ──
  # Config with NTLM hash lives at /etc/cntlm.conf (NOT in git — contains credential hash)
  # First-time setup:
  #   sudo tee /etc/cntlm.conf << 'EOF'
  #   Username    YehiaAmer
  #   Domain      BKU
  #   Auth        NTLMv2
  #   PassNTLMv2  <YOUR_HASH>
  #   Proxy       10.136.62.193:8080
  #   NoProxy     localhost, 127.0.0.*
  #   Listen      3128
  #   EOF
  #   sudo chmod 600 /etc/cntlm.conf
  # Generate hash: cntlm -H -d BKU -u YehiaAmer 10.136.62.193:8080
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    cntlm
    cloudflared  # for Cloudflare Tunnel (SSH access to this machine)
    libsecret
    gnome-keyring
    dbus
  ];

  systemd.services.cntlm = {
    description = "CNTLM NTLM authenticating proxy";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.cntlm}/bin/cntlm -c /etc/cntlm.conf -v -f";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  # ── DNS (fully independent — own dnsmasq + cloudflared) ──
  networking.resolvconf.enable = false;
  environment.etc."resolv.conf".text = ''
    nameserver 127.0.0.53
  '';

  # dnsmasq: split DNS (corp → corp DNS, external → cloudflared DoH)
  services.dnsmasq = {
    enable = true;
    settings = {
      server = [
        "/db.de/10.255.255.254"
        "/rz.db.de/10.255.255.254"
        "127.0.0.1#5053"
      ];
      no-resolv = true;
      listen-address = "127.0.0.53";
      bind-interfaces = true;
    };
  };

  # dnscrypt-proxy: DNS-over-HTTPS (replaces deprecated cloudflared proxy-dns)
  services.dnscrypt-proxy = {
    enable = true;
    settings = {
      listen_addresses = [ "127.0.0.1:5053" ];
      server_names = [ "cloudflare" "cloudflare-ipv6" "google" ];
      # Use cntlm proxy to reach DoH servers
      http_proxy = "http://127.0.0.1:3128";
      # Performance
      cache = true;
      cache_size = 4096;
    };
  };

  # cloudflared tunnel (SSH + services access to this machine)
  # Credentials at ~/.cloudflared/ (NOT in git — contains TunnelSecret)
  systemd.services.cloudflared-tunnel = {
    description = "Cloudflare Tunnel";
    after = [ "network.target" "cntlm.service" ];
    wants = [ "cntlm.service" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      HTTP_PROXY = "http://127.0.0.1:3128";
      HTTPS_PROXY = "http://127.0.0.1:3128";
    };
    serviceConfig = {
      User = "yamer003";
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --config /home/yamer003/.cloudflared/config.yml run";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Enable SSH server (for cloudflared tunnel access)
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # PostgreSQL for local development in WSL
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    settings = {
      listen_addresses = lib.mkForce "127.0.0.1,::1";
    };
    ensureDatabases = [ "yamer003" ];
    ensureUsers = [
      {
        name = "yamer003";
        ensureDBOwnership = true;
      }
    ];
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
  programs.zsh.interactiveShellInit = ''
    # Override WSL-inherited proxy vars with correct local cntlm proxy
    export HTTP_PROXY="http://127.0.0.1:3128"
    export HTTPS_PROXY="http://127.0.0.1:3128"
    export http_proxy="http://127.0.0.1:3128"
    export https_proxy="http://127.0.0.1:3128"
    export NO_PROXY="localhost,127.0.0.1,::1,.db.de,.rz.db.de"
    export no_proxy="localhost,127.0.0.1,::1,.db.de,.rz.db.de"
    export NODE_USE_ENV_PROXY=1

    # Auto-unlock gnome-keyring (WSL has no PAM login to do this)
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    if [[ ! -S "$XDG_RUNTIME_DIR/keyring/control" ]]; then
      echo "" | gnome-keyring-daemon --unlock --components=secrets &>/dev/null
    fi
  '';

  # Allow wheel group passwordless sudo (convenient for WSL)
  security.sudo.wheelNeedsPassword = false;


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

  # Patch pi shebang to use bun (bun's fetch respects HTTP_PROXY natively,
  # Node.js + undici's EnvHttpProxyAgent doesn't work reliably behind corp proxy)
  # Re-run `sudo nixos-rebuild switch` after `bun update -g @mariozechner/pi-coding-agent`
  system.userActivationScripts.piWrapper = ''
    PI_CLI="/home/yamer003/.bun/install/global/node_modules/@mariozechner/pi-coding-agent/dist/cli.js"
    if [ -f "$PI_CLI" ] && head -1 "$PI_CLI" | grep -q "node"; then
      sed -i '1s|#!/usr/bin/env node|#!/usr/bin/env bun|' "$PI_CLI"
    fi
  '';

  services.vscode-server.enable = true;

  system.stateVersion = "24.11";
}
