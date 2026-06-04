# Shared packages — cross-platform CLI tools
{ pkgs, ... }:
{
  home.packages = with pkgs; [

    # AI & ML
    gollama
    ollama

    # CLI Utilities
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
    kubectl
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

    # Development - Package Managers
    fnm
    pipenv
    pnpm
    poetry
    uv
    yarn

    # Development - Tools
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
