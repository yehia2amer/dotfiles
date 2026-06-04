# ~/.config/fish/local.fish — Managed by Chezmoi
# Sourced by Home Manager's fish framework via interactiveShellInit

# ── Essential PATHs ──
fish_add_path -g /etc/profiles/per-user/$USER/bin
fish_add_path -g $HOME/.nix-profile/bin
fish_add_path -g $HOME/.local/bin
fish_add_path -g $HOME/.krew/bin
fish_add_path -g /opt/podman/bin

# ── Container runtime (podman as docker drop-in) ──
set -gx KIND_EXPERIMENTAL_PROVIDER podman
fish_add_path -g $HOME/.bun/bin
fish_add_path -g $HOME/.npm-global/bin
fish_add_path -g $HOME/.rd/bin
fish_add_path -g $HOME/.atuin/bin
fish_add_path -g $HOME/.cargo/bin

# Added by LM Studio CLI (lms)
fish_add_path -g $HOME/.lmstudio/bin
