# Published, hash-pinned inputs from the Omarchy-M4-Native project.
# The hex hashes are the ones that project pins in its own tree or release:
#   payload: packaging/omarchy-m4/linux-m4-omarchy/PKGBUILD (pkgrel 2)
#   Image.gz: packaging/omarchy-m4/channel.json kernel.image_sha256
#   dtb: tools/m4-boot-compose.py KNOWN_DTBS 'j713-cpu-temperature'
#   loader: the update 4 installer's installer_data.json m4_boot.loader
{
  lib,
  fetchurl,
  runCommand,
  python3,
  cacert,
  patchutils,
  gnupatch,
}:
let
  base = "https://github.com/Kb2uka/Omarchy-M4-Native/releases/download";
  update4 = "${base}/v0.1.0-alpha.1-update.4/omarchy-j713-v0.1.0-alpha.1-update.4-os";
  # Omarchy-M4-Native commit whose patches/installer matches the update 4
  # installer's source (src/m4boot.py is byte-identical).
  installerRevision = "6c6d2e4dd48b6306416c28686b5212b6bc4f77dc";
in
rec {
  kernelPayload = fetchurl {
    url = "${base}/package-inputs/linux-m4-omarchy-7.1.9.m4.20261008-payload.tar.zst";
    # b160686fa06c437343f85aab10be41a669f2a23106b7e4e83e0911c921e6388f
    hash = "sha256-sWBob6BsQ3ND+FqrEL5BpmnyojEGt+ToPgkRySHmOI8=";
  };
  kernelImageSha256 = "c3704cfd2afb7760e73f0b9939a68864a30bd916fcd478bd960e538373123dc9";

  # Lineage: alpha.1 base -> update.1 (SMC poweroff cells) -> bounded cpufreq
  # (E 900 MHz, P up to 1800 MHz, the clocks iBoot hands over) -> reporting-only
  # CPU die temperature. Nothing later: no E-cluster raise, no P boost, no front
  # USB-C port, no backlight.
  dtb = fetchurl {
    url = "${base}/package-inputs/j713-cputemp.dtb";
    # 08e8e719381f88a1e50d821c145dad5b2d97fd772609e13d7778e19795e9cad1
    hash = "sha256-COjnGTgfiKHlDYIcFF2tWy2X/XcmCeE9d3jhl5XpytE=";
  };

  # m1n1 stage 2, boot/loader.bin in the update 4 OS ZIP. Only the ZIP's
  # central directory and this member are downloaded, not the 4.4 GB archive.
  loader =
    runCommand "j713-m1n1-stage2-3a3f7a64.bin"
      {
        nativeBuildInputs = [ python3 ];
        SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
        outputHashMode = "flat";
        outputHashAlgo = "sha256";
        # 3a3f7a64c65fc366d5ac9aece3e1bee64119be012aa1ec5b15d2743c6f91fce4
        outputHash = "sha256-Oj96ZMZfw2bVrJrs4+G+5kEZvgEqoexbFdJ0PG+R/OQ=";
      }
      ''
        python3 -I ${./fetch-zip-member.py} boot/loader.bin $out \
          ${update4}.part001:1900000000 \
          ${update4}.part002:1900000000 \
          ${update4}.part003:640455967
      '';

  # The update 4 installer bundle (patched asahi-installer, m1n1 stage 1 with
  # the #82 fix, Python framework) and its license notices, unchanged, from
  # the 1.4 GB companion tar. Only these members are downloaded.
  installerKit =
    runCommand "j713-installer-update4"
      {
        nativeBuildInputs = [ python3 ];
        SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
        outputHash = "sha256-PgIjQZSKVTh6x3+QshHYeLQrK1pn7xujUrrOcq7vlCA=";
      }
      ''
                mkdir $out
                python3 -I ${./fetch-tar-member.py} \
                  ${base}/v0.1.0-alpha.1-update.4/omarchy-j713-v0.1.0-alpha.1-update.4-companion.tar $out \
                  installer-macos.tar.gz notices/LICENSE.md notices/THIRD_PARTY_NOTICES.md \
                  notices/LICENSES/Gravity-installer-MIT.txt notices/LICENSES/ISC.txt
                cd $out
                sha256sum -c - <<'EOF'
        73c1981f606fd9be4139bd55f3d95988f5d608f96991ebec79c687b5dd6e662b  installer-macos.tar.gz
        f78a2b723bf6c758cf2c05d641f6669fb2aa677fc39c3b5cc773703cd0f7d414  notices/LICENSE.md
        dedee97e8dc8ced621589629acfa3b52401d146f5c219ce1b53dd5dd8d123693  notices/THIRD_PARTY_NOTICES.md
        811207d92b81da5b5e97cdfa52542769d8783325da5b422262ccecfa2d23c5a9  notices/LICENSES/Gravity-installer-MIT.txt
        f2ec607f67bb0dd3053b49835b02110d5cd0f8eb6da3aac4dc0b142a6b299be9  notices/LICENSES/ISC.txt
                EOF
      '';

  installerPatch = fetchurl {
    url = "https://raw.githubusercontent.com/Kb2uka/Omarchy-M4-Native/${installerRevision}/patches/installer/root-identity.patch";
    # 8f3c658cea986827b243e9ca14b55991b40ae7b08eeb81c9b77f29a98f6d3d28
    hash = "sha256-jzxljOqYaCeyQ+nKFLVZkbQK57CO64HJt38pqY9tPSg=";
  };

  # The installer's src/m4boot.py, which writes boot.bin at install time.
  # Used by tests to check m4-nix-boot against the installer's own layout.
  installerM4boot =
    runCommand "installer-m4boot.py"
      {
        nativeBuildInputs = [
          patchutils
          gnupatch
        ];
      }
      ''
        mkdir tree
        filterdiff -i '*/src/m4boot.py' ${installerPatch} | (cd tree && patch -p1 -s)
        install -m444 tree/src/m4boot.py $out
      '';
}
