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
    in
    {
      nixosModules.default = ./modules/j713.nix;

      nixosConfigurations.minimal = nixpkgs.lib.nixosSystem {
        modules = [
          self.nixosModules.default
          ./examples/minimal/configuration.nix
          { nixpkgs.hostPlatform = "aarch64-linux"; }
        ];
      };

      packages = forAll (
        pkgs:
        {
          m4-nix-boot = pkgs.callPackage ./pkgs/m4-nix-boot { };
          # The installer kit; data assembly runs on this system's own tools.
          kit = pkgs.callPackage ./pkgs/kit { nixos = minimal; };
          minimal = minimal.config.system.build.toplevel;
        }
        // nixpkgs.lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "aarch64-linux") {
          linux-m4 = pkgs.callPackage ./pkgs/linux-m4.nix { kernelPatches = [ ]; };
        }
      );

      checks = forAll (pkgs: {
        m4-nix-boot = self.packages.${pkgs.stdenv.hostPlatform.system}.m4-nix-boot;
        policy = import ./tests/policy.nix {
          inherit pkgs;
          nixos = minimal;
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
