# Python, libffi and the CA bundle are the only parts not built from source.
{
  lib,
  stdenvNoCC,
  callPackage,
  fetchurl,
  libarchive,
  cpio,
  librsvg,
  libicns,
  cacert,
  m1n1Stage1,
}:
let
  python = fetchurl {
    url = "https://www.python.org/ftp/python/3.13.9/python-3.13.9-macos11.pkg";
    hash = "sha256-2v6/YrhzfzQfa37KLW0RU6UKaxv7+kuKrw5ircc+UBc=";
  };
  # The registry's anonymous token for public bottles.
  libffi = fetchurl {
    name = "libffi-3.5.2.arm64_tahoe.bottle.tar.gz";
    url = "https://ghcr.io/v2/homebrew/core/libffi/blobs/sha256:564ce412bbf20deb184e488fe9b1cbf94b5c770965e48567c829a5f580141a95";
    hash = "sha256-VkzkErvyDesYTkiP6bHL+Utcdwll5IVnyCml9YAUGpU=";
    curlOptsList = [
      "-H"
      "Authorization: Bearer QQ=="
    ];
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "firn-installer";
  version = "0-unstable-2026-10-02";

  src = callPackage ./source.nix { };

  nativeBuildInputs = [
    libarchive
    cpio
    librsvg
    libicns
  ];

  buildPhase = ''
    runHook preBuild

    mkdir -p package/bin package/boot
    cp -r src/* package/
    rm package/asahi_firmware
    cp -r asahi_firmware package/
    install -m444 ${m1n1Stage1}/lib/m1n1/m1n1.bin package/boot/m1n1.bin

    for size in 16 32 128 256 512; do
      rsvg-convert -w $size -h $size ${./logo.svg} -o logo-$size.png
    done
    png2icns package/logo.icns logo-*.png

    framework=package/Frameworks/Python.framework
    mkdir -p $framework
    bsdtar -xOf ${python} Python_Framework.pkg/Payload | gzip -dc | (cd $framework && cpio -i --quiet)
    tar -xzf ${libffi}
    mv libffi/3.5.2/lib/libffi*.dylib $framework/Versions/Current/lib/

    # As upstream's build.sh.
    rm -rf $framework/Versions/Current/{include,share}
    (cd $framework/Versions/Current/lib && rm -rf -- tdb* tk* Tk* libtk* *tcl*)
    (cd $framework/Versions/Current/lib/python3.13 && rm -rf test ensurepip idlelib)
    rm -f $framework/Versions/Current/lib/python3.13/lib-dynload/{_test*,_tkinter*}
    install -m444 ${cacert}/etc/ssl/certs/ca-bundle.crt $framework/Versions/Current/etc/openssl/cert.pem

    echo firn-${finalAttrs.version} > package/version.tag

    mkdir notices
    install -m444 LICENSE notices/asahi-installer.txt
    install -m444 ${m1n1Stage1.src}/LICENSE notices/m1n1.txt
    cp -r ${m1n1Stage1.src}/3rdparty_licenses notices/m1n1-3rdparty
    install -m444 $framework/Versions/Current/lib/python3.13/LICENSE.txt notices/python.txt
    install -m444 libffi/3.5.2/LICENSE notices/libffi.txt
    echo "The CA bundle (Frameworks/Python.framework/Versions/Current/etc/openssl/cert.pem) is Mozilla's, under MPL-2.0: https://www.mozilla.org/MPL/2.0/" \
      > notices/ca-bundle.txt

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    tar -C package --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner -cf - . \
      | gzip -9n > $out/installer.tar.gz
    cp -r notices $out/notices
    chmod -R u+w $out/notices
    runHook postInstall
  '';

  meta = {
    description = "macOS-side installer for Firn on the 13-inch M4 MacBook Air";
    license = lib.licenses.mit;
  };
})
