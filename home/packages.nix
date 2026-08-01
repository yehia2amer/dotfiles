# Shared packages — cross-platform CLI tools
{ pkgs, lib, ... }:
{
  home.packages = with pkgs; [

    # AI & ML
    beads
    claude-code
    gollama
    github-copilot-cli
    ollama
    rtk
    (writeShellScriptBin "claude-remote" ''
      set -euo pipefail
      umask 077

      happy_bin="$HOME/.local/bin/happy"
      if [[ ! -x "$happy_bin" ]]; then
        echo "Happy is not installed at $happy_bin." >&2
        echo "Install it with: npm install -g --prefix \"$HOME/.local\" happy@1.2.0" >&2
        exit 1
      fi

      exec "$happy_bin" claude \
        --happy-starting-mode remote \
        --permission-mode default \
        --model bedrock.anthropic.claude-opus-5 \
        "$@"
    '')

    # CLI Utilities
    ast-grep
    bat
    bottom
    coreutils
    dua
    exiftool
    f2
    fd
    fzf
    hyperfine
    jq
    procs
    ripgrep
    sd
    tealdeer
    tree
    yq
    yt-dlp

    # Cloud & Infrastructure
    awscli2
    azure-cli
    cloudflared
    opentofu
    pulumi
    pulumiPackages.pulumi-python
    vault-bin

    # Containers & Kubernetes
    argocd
    cilium-cli
    fluxcd
    kubernetes-helm
    istioctl
    k3d
    k9s
    kind
    krew
    kubecm
    kubeconform
    (lib.hiPrio kubectl)
    kubectl-cnpg
    kubectx
    kubie
    kustomize
    minikube
    talosctl

    # Database
    dolt
    duckdb
    redis

    # Development - Editor
    neovim

    # Development - Languages
    bun
    deno
    go
    jdk
    llvm
    nodejs
    python313
    rustc
    typescript-go

    # Development - Package Managers
    fnm
    pipenv
    pnpm
    (if stdenv.isDarwin then
      (poetry.overridePythonAttrs (old: {
        # nixpkgs-unstable: output formatting differs on Darwin; 3,065 other tests pass.
        disabledTests = (old.disabledTests or [ ]) ++ [
          "test_execute_executes_a_batch_of_operations"
          "test_execute_prints_warning_for_yanked_package"
        ];
      }))
    else poetry)
    uv
    yarn

    # Development - Tools
    android-tools
    androidenv.androidPkgs.ndk-bundle
    automake
    biome
    cmake
    delta
    delve
    dprint
    gh
    git
    git-lfs
    glab
    go-tools
    golangci-lint
    gopls
    just
    lefthook
    maven
    pkgconf
    pre-commit
    protobuf
    pyright
    ruff

    # File Tools
    _7zz
    e2fsprogs
    p7zip

    # Media & Documents
    ffmpeg
    imagemagick
    mdbook
    mkdocs
    mpv
    poppler
    scrcpy

    # Networking
    croc
    hey
    iperf3
    k6
    minicom
    (if pkgs.stdenv.isDarwin then
      (rclone.overrideAttrs (_: {
        buildInputs = [ (pkgs.macfuse-stubs.override { isFuse3 = false; }) ];
        tags = [ "cmount" ];
      }))
    else rclone)
    rsync
    sshpass

    # Security & Scanning
    binwalk
    gnupg
    gosec
    gitleaks
    nmap
    rustscan
    trivy
    trufflehog

    # Dotfiles Management
    chezmoi

    # Shell & Terminal
    atuin
    carapace
    fish
    nushell
    prek
    starship
    tmux
    yazi
    zellij
    zoxide

    # Virtualization
    libvirt
    qemu

    # Other
    SDL2
    acpica-tools
    act
    air
    capstone
    cargo-binstall
    cargo-depgraph
    cargo-make
    cmctl
    code2prompt
    consul-template
    cookiecutter
    cunit
    gd
    golangci-lint-langserver
    graphviz
    icu
    inetutils
    libass
    libgit2
    libuchardet
    openfga
    postgresql_17
    protoc-gen-go
    protoc-gen-go-grpc
    resvg
    rm-improved
    speedtest-cli
    supabase-cli
    tailwindcss
    testkube
    tex-fmt
    tree-sitter
    unixodbc
    vapoursynth
    yo
  ];
}
