{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.firn;
in
{
  options.hardware.firn.mesa = lib.mkOption {
    type = lib.types.package;
    default = pkgs.callPackage ../pkgs/mesa { };
    defaultText = lib.literalMD "Mesa from Gravity Linux, built by `pkgs/mesa`";
    description = ''
      Mesa with the asahi drivers for the M4's GPU, used for graphics when
      hardware.graphics is on. Its `opencl` output holds the OpenCL driver.
    '';
  };

  config = lib.mkIf cfg.enable {
    # Above NixOS's mkDefault of nixpkgs' Mesa, below a plain setting.
    hardware.graphics.package = lib.mkOverride 999 cfg.mesa;
  };
}
