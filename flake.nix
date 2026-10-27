{
  description = "NixOS on the 13-inch M4 MacBook Air (J713), built on Omarchy-M4-Native's hardware work";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      minimal = self.nixosConfigurations.minimal;

      # The M4 Mesa replaces mesa in every stage, so a cross build takes its
      # asahi_clc from the same source.
      m4Overlay = final: prev: {
        mesa = prev.callPackage ./pkgs/mesa { inherit (prev) mesa; };
      };
      # aarch64-linux package set built on (and, if foreign, cross-compiled from) system.
      aarch64From =
        system:
        import nixpkgs {
          localSystem = system;
          crossSystem = if system == "aarch64-linux" then null else "aarch64-linux";
          overlays = [ m4Overlay ];
        };
    in
    {
      nixosModules.default = ./modules;

      nixosConfigurations.minimal = nixpkgs.lib.nixosSystem {
        modules = [
          self.nixosModules.default
          ./examples/minimal/configuration.nix
          { nixpkgs.hostPlatform = "aarch64-linux"; }
        ];
      };

      packages = forAll (
        pkgs:
        let
          # Built natively on aarch64, cross-compiled elsewhere.
          aarch64 = aarch64From pkgs.stdenv.hostPlatform.system;
        in
        {
          m4-nix-boot = pkgs.callPackage ./pkgs/m4-nix-boot { };
          # The installer kit; data assembly runs on this system's own tools.
          kit = pkgs.callPackage ./pkgs/kit { nixos = minimal; };
          minimal = minimal.config.system.build.toplevel;
          linux = aarch64.callPackage ./pkgs/linux { kernelPatches = [ ]; };
          inherit (aarch64) mesa;
          m1n1 = aarch64.callPackage ./pkgs/m1n1 { };
        }
      );

      checks = forAll (pkgs: {
        m4-nix-boot = self.packages.${pkgs.stdenv.hostPlatform.system}.m4-nix-boot;
        policy = import ./tests/policy.nix {
          inherit pkgs;
          nixos = minimal;
        };
        kernel-modules = import ./tests/kernel-modules.nix {
          inherit pkgs;
          kernel = self.packages.${pkgs.stdenv.hostPlatform.system}.linux;
        };
        devicetree = import ./tests/devicetree {
          inherit pkgs;
          kernel = self.packages.${pkgs.stdenv.hostPlatform.system}.linux;
          releaseDtb = (pkgs.callPackage ./pkgs/sources.nix { }).dtb;
        };
        devicetree-schema = import ./tests/devicetree/schema.nix {
          inherit pkgs;
          kernel = self.packages.${pkgs.stdenv.hostPlatform.system}.linux;
        };
        # Needs an aarch64 builder (binfmt on x86_64) for the system itself.
        vm-boot = import ./tests/vm {
          inherit pkgs;
          nixos = minimal;
        };
      });

      formatter = forAll (pkgs: pkgs.nixfmt);
    };
}
