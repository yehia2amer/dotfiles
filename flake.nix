{
  description = "Yehia Amer's multi-machine Nix config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    systems.url = "github:nix-systems/default-linux";

    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.inputs.systems.follows = "systems";
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, nixos-wsl, vscode-server, ... }:
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
      modules = [
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
