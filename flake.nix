{
  description = "Yehia Amer's multi-machine Nix config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };

    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };

    homebrew-freetonik-tap = {
      url = "github:freetonik/homebrew-tap";
      flake = false;
    };

    homebrew-gimlet-capacitor = {
      url = "github:gimlet-io/homebrew-capacitor";
      flake = false;
    };

    homebrew-jundot-omlx = {
      url = "github:jundot/omlx";
      flake = false;
    };

    homebrew-multica-tap = {
      url = "github:multica-ai/homebrew-tap";
      flake = false;
    };

    homebrew-surrealdb-tap = {
      url = "github:surrealdb/homebrew-tap";
      flake = false;
    };

    homebrew-theykk-tap = {
      url = "github:TheYkk/homebrew-tap";
      flake = false;
    };

    homebrew-us-tap = {
      url = "github:us/homebrew-tap";
      flake = false;
    };

    homebrew-veracode-tap = {
      url = "github:veracode/homebrew-tap";
      flake = false;
    };

    homebrew-wouterdebie-tap = {
      url = "github:wouterdebie/homebrew-tap";
      flake = false;
    };

    vscode-server.url = "github:nix-community/nixos-vscode-server";

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, nix-darwin, home-manager, nix-homebrew, nixos-wsl, vscode-server, ... }:
  let
    systems = {
      darwin = "aarch64-darwin";
      linux = "x86_64-linux";
    };
  in
  {
    # ── macOS (nix-darwin + Home Manager) ──
    darwinConfigurations."MacBookProM3" = nix-darwin.lib.darwinSystem {
      system = systems.darwin;
      specialArgs = { inherit inputs; };
      modules = [
        nix-homebrew.darwinModules.nix-homebrew
        ./nix/darwin
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "bak";
          home-manager.users.yamer003 = { pkgs, ... }: {
            imports = [ ./home ];
            home.homeDirectory = "/Users/yamer003";
          };
        }
      ];
    };

    # ── NixOS Laptop ──
    nixosConfigurations."nixos-laptop" = nixpkgs.lib.nixosSystem {
      system = systems.linux;
      modules = [
        ./nix/nixos/laptop.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "bak";
          home-manager.users.yamer003 = import ./home;
        }
      ];
    };

    # ── NixOS Server ──
    nixosConfigurations."nixos-server" = nixpkgs.lib.nixosSystem {
      system = systems.linux;
      modules = [
        ./nix/nixos/server.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "bak";
          home-manager.users.yamer003 = import ./home;
        }
      ];
    };

    # ── NixOS WSL ──
    nixosConfigurations."nixos-wsl" = nixpkgs.lib.nixosSystem {
      system = systems.linux;
      modules = [
        nixos-wsl.nixosModules.wsl
        vscode-server.nixosModules.default
        ./nix/nixos/wsl.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "bak";
          home-manager.users.yamer003 = import ./home;
        }
      ];
    };

    # ── Standalone Home Manager (for bootstrapping without system rebuild) ──
    homeConfigurations = {
      "yamer003@MacBookProM3" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { system = systems.darwin; config.allowUnfree = true; };
        modules = [ ./home ];
      };
      "yamer003@nixos-laptop" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { system = systems.linux; config.allowUnfree = true; };
        modules = [ ./home ];
      };
    };
  };
}
