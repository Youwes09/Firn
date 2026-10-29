{
  description = "Firn: NixOS on the 13-inch M4 MacBook Air (J713)";

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

      aarch64From =
        system:
        import nixpkgs {
          localSystem = system;
          crossSystem = if system == "aarch64-linux" then null else "aarch64-linux";
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
          aarch64 = aarch64From pkgs.stdenv.hostPlatform.system;
          packages = self.packages.${pkgs.stdenv.hostPlatform.system};
        in
        {
          firn-boot = pkgs.callPackage ./pkgs/firn-boot { };
          installer = pkgs.callPackage ./pkgs/installer { m1n1Stage1 = packages.m1n1-stage1; };
          kit = pkgs.callPackage ./pkgs/kit {
            nixos = minimal;
            inherit (packages) installer;
          };
          minimal = minimal.config.system.build.toplevel;
          linux = aarch64.callPackage ./pkgs/linux { kernelPatches = [ ]; };
          m1n1-stage1 = aarch64.callPackage ./pkgs/m1n1 { stage = 1; };
          m1n1-stage2 = aarch64.callPackage ./pkgs/m1n1 { stage = 2; };
        }
      );

      checks = forAll (
        pkgs:
        let
          packages = self.packages.${pkgs.stdenv.hostPlatform.system};
        in
        {
          firn-boot = packages.firn-boot;
          policy = import ./tests/policy.nix {
            inherit pkgs;
            nixos = minimal;
          };
          kernel-modules = import ./tests/kernel-modules.nix {
            inherit pkgs;
            kernel = packages.linux;
          };
          devicetree-schema = import ./tests/devicetree-schema.nix {
            inherit pkgs;
            kernel = packages.linux;
          };
          # Needs an aarch64 builder.
          vm-boot = import ./tests/vm {
            inherit pkgs;
            nixos = minimal;
          };
        }
      );

      formatter = forAll (pkgs: pkgs.nixfmt);
    };
}
