{
  config,
  inputs,
  lib,
  ...
}:
let
  primaryUser = "yamer003";
  brew = "/opt/homebrew/bin/brew";
  brewCompletion = "${config.nix-homebrew.package}/completions/zsh/_brew";
  varlockVersion = "1.13.0";
in
{
  nix-homebrew = {
    enable = true;
    autoMigrate = false;
    enableRosetta = false;
    user = primaryUser;
    mutableTaps = false;

    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
      "freetonik/homebrew-tap" = inputs.homebrew-freetonik-tap;
      "gimlet-io/homebrew-capacitor" = inputs.homebrew-gimlet-capacitor;
      "jundot/homebrew-omlx" = inputs.homebrew-jundot-omlx;
      "multica-ai/homebrew-tap" = inputs.homebrew-multica-tap;
      "surrealdb/homebrew-tap" = inputs.homebrew-surrealdb-tap;
      "theykk/homebrew-tap" = inputs.homebrew-theykk-tap;
      "us/homebrew-tap" = inputs.homebrew-us-tap;
      "veracode/homebrew-tap" = inputs.homebrew-veracode-tap;
      "wouterdebie/homebrew-tap" = inputs.homebrew-wouterdebie-tap;
    };

    trust = {
      formulae = [
        "freetonik/tap/textpod"
        "gimlet-io/capacitor/capacitor"
        "jundot/omlx/omlx"
        "multica-ai/tap/multica"
        "surrealdb/tap/surreal"
        "theykk/tap/git-switcher"
        "us/tap/mocker"
        "veracode/tap/veracode-cli"
      ];
      casks = [ "wouterdebie/tap/davit" ];
      commands = [ ];
      taps = [ ];
    };
  };

  homebrew = {
    enable = true;
    user = primaryUser;

    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
      extraEnv = {
        HOMEBREW_NO_ANALYTICS = "1";
        HOMEBREW_NO_ENV_HINTS = "1";
      };
    };

    global.autoUpdate = false;

    taps = builtins.attrNames config.nix-homebrew.taps;

    brews = [
      "bitwarden-cli"
      "container"
      "dnspyre"
      "freetonik/tap/textpod"
      "gimlet-io/capacitor/capacitor"
      "jundot/omlx/omlx"
      "livekit-cli"
      "mole"
      "multica-ai/tap/multica"
      "pi-coding-agent"
      "theykk/tap/git-switcher"
      "us/tap/mocker"
      "varlock"
      "veracode/tap/veracode-cli"
      "virtctl"
    ];

    casks = [
      "bitwarden"
      "codex"
      "wouterdebie/tap/davit"
      "thaw"
    ];
  };

  environment.variables = {
    HOMEBREW_NO_ANALYTICS = "1";
    HOMEBREW_NO_ENV_HINTS = "1";
  };

  # Keep the security-sensitive dotenv validator on the reviewed release.
  # nix-darwin runs postActivation after its Homebrew Bundle activation.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    mkdir -p /opt/homebrew/share/zsh/site-functions
    ln -sfn ${brewCompletion} /opt/homebrew/share/zsh/site-functions/_brew

    if [ -x ${brew} ]; then
      # Stage 1 recorded Davit as both formula and cask trust. Keep only its
      # cask trust entry.
      sudo --user=${primaryUser} --set-home ${brew} untrust --formula wouterdebie/tap/davit >/dev/null 2>&1 || true

      varlock_versions="$(sudo --user=${primaryUser} --set-home ${brew} list --versions varlock 2>/dev/null || true)"
      if [ "$varlock_versions" != "varlock ${varlockVersion}" ]; then
        echo >&2 "error: expected varlock ${varlockVersion}, found: ''${varlock_versions:-not installed}"
        exit 1
      fi

      sudo --user=${primaryUser} --set-home ${brew} pin varlock >/dev/null
    fi
  '';
}
