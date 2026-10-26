#!/usr/bin/env python3
"""Make what the J713 installer would write for a generation, for the VM test.

Writes boot.bin with the installer's own m4boot.compose, using a stand-in
firmware archive in the installer's /vendorfw layout, and the initramfs and
boot arguments inside it for QEMU to boot directly.
"""
import argparse
import importlib.util
from pathlib import Path
import sys
import tarfile
import tempfile

FIRMWARE = [
    ('vendorfw', 0o40755, b''),
    ('vendorfw/.vendorfw.manifest', 0o100644, b'm4-nix VM stand-in\n'),
    ('vendorfw/brcm', 0o40755, b''),
    ('vendorfw/brcm/m4-nix-test.bin', 0o100644, b'm4-nix-test-firmware'),
]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def cpio(entries):
    out = bytearray()
    for ino, (name, mode, body) in enumerate(entries + [('TRAILER!!!', 0, b'')]):
        encoded = name.encode() + b'\0'
        fields = (ino, mode, 0, 0, 1, 0, len(body), 0, 0, 0, 0, len(encoded), 0)
        out += b'070701' + b''.join(b'%08X' % value for value in fields) + encoded
        out += bytes(-len(out) % 4)
        out += body
        out += bytes(-len(out) % 4)
    return bytes(out)


def main():
    parser = argparse.ArgumentParser()
    for name in ('installer-bundle', 'nix-boot', 'loader', 'toplevel', 'out'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    out, toplevel = Path(args.out), Path(args.toplevel)
    nix_boot = load('m4_nix_boot', args.nix_boot)
    with tempfile.TemporaryDirectory() as scratch:
        with tarfile.open(args.installer_bundle) as archive:
            archive.extract('./m4boot.py', scratch, filter='data')
        m4boot = load('m4boot', Path(scratch, 'm4boot.py'))

    params = (toplevel / 'kernel-params').read_text().split()
    line = nix_boot.bootargs_line(params, str(toplevel / 'init'))
    bootargs = line[len(nix_boot.BOOTARGS):-1].decode()
    parts = {
        'loader': Path(args.loader).read_bytes(),
        'kernel': (toplevel / 'kernel').read_bytes(),
        'dtb': (toplevel / 'dtbs' / 'apple' / 'm4-nix-j713.dtb').read_bytes(),
        'initramfs': (toplevel / 'initrd').read_bytes(),
    }
    firmware = cpio(FIRMWARE)
    nix_boot.check_firmware(firmware)
    bootbin = m4boot.compose(parts, bootargs, firmware)
    layout = nix_boot.parse(bootbin)
    out.mkdir(parents=True, exist_ok=True)
    (out / 'boot.bin').write_bytes(bootbin)
    (out / 'initramfs.img').write_bytes(layout['initramfs'])
    (out / 'bootargs.txt').write_text(bootargs)


if __name__ == '__main__':
    sys.exit(main())
