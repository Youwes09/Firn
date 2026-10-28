#!/usr/bin/env python3
"""Make what the installer would write for a generation, for the VM test.

Writes boot.bin with the installer's own payloads.build, using a stand-in
firmware archive in the installer's /vendorfw layout, and the initramfs and
boot arguments inside it for QEMU to boot directly.
"""
import argparse
import importlib.util
from pathlib import Path
import sys

FIRMWARE = [
    ('vendorfw', 0o40755, b''),
    ('vendorfw/.vendorfw.manifest', 0o100644, b'firn VM stand-in\n'),
    ('vendorfw/brcm', 0o40755, b''),
    ('vendorfw/brcm/firn-test.bin', 0o100644, b'firn-test-firmware'),
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
    for name in ('payloads', 'firn-boot', 'toplevel', 'out'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    out, toplevel = Path(args.out), Path(args.toplevel)
    firn_boot = load('firn_boot', args.firn_boot)
    payloads = load('payloads', args.payloads)

    params = (toplevel / 'kernel-params').read_text().split()
    line = firn_boot.bootargs_line(params, str(toplevel / 'init'))
    bootargs = line[len(firn_boot.BOOTARGS):-1].decode()
    parts = {
        'm1n1': (toplevel / 'm1n1.bin').read_bytes(),
        'kernel': (toplevel / 'kernel').read_bytes(),
        'dtb': (toplevel / firn_boot.DTB).read_bytes(),
        'initramfs': (toplevel / 'initrd').read_bytes(),
    }
    firmware = cpio(FIRMWARE)
    firn_boot.check_firmware(firmware)
    bootbin = payloads.build(parts, bootargs, firmware)
    layout = firn_boot.parse(bootbin)
    out.mkdir(parents=True, exist_ok=True)
    (out / 'boot.bin').write_bytes(bootbin)
    (out / 'initramfs.img').write_bytes(layout['initramfs'])
    (out / 'bootargs.txt').write_text(bootargs)


if __name__ == '__main__':
    sys.exit(main())
