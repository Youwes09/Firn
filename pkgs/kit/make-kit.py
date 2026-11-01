#!/usr/bin/env python3
"""Assemble the installer kit and check it with the installer's own code."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import zipfile

PACKAGE = 'firn-j713.zip'
# The display driver supports this firmware's DCP interface.
STUB_FIRMWARE = '26.6.2'


def sha(path):
    with open(path, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def require(condition, message):
    if not condition:
        raise SystemExit('make-kit: ' + message)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def stand_in_firmware():
    """A minimal firmware archive in the installer's /vendorfw layout."""
    entries = [('vendorfw', 0o40755, b''), ('vendorfw/.vendorfw.manifest', 0o100644, b'stand-in\n')]
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
    for name in ('installer', 'installer-src', 'firn-boot', 'root-image', 'loader', 'kernel', 'dtb',
                 'initrd', 'kernel-params', 'init', 'os-name', 'install-command', 'preflight',
                 'start-here', 'guide', 'out'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir()

    firn_boot = load('firn_boot', args.firn_boot)
    sys.path.insert(0, str(Path(args.installer_src, 'src')))
    import osinstall
    import payloads

    params = Path(args.kernel_params).read_text().split()
    line = firn_boot.bootargs_line(params, args.init)
    bootargs = line[len(firn_boot.BOOTARGS):-1].decode()

    parts = {
        'm1n1': ('boot/m1n1.bin', args.loader),
        'kernel': ('boot/Image.gz', args.kernel),
        'dtb': ('boot/t8132-j713.dtb', args.dtb),
        'initramfs': ('boot/initramfs.cpio.gz', args.initrd),
    }
    root_bytes = os.path.getsize(args.root_image)
    require(root_bytes % (1 << 20) == 0, 'root image is not a whole number of MiB')
    entry = {
        'name': args.os_name + ' (NixOS, experimental)',
        'default_os_name': args.os_name,
        'expert': False,
        'boot_object': 'm1n1.bin',
        'next_object': 'm1n1/boot.bin',
        'package': PACKAGE,
        'supported_fw': [STUB_FIRMWARE],
        'partitions': [
            {'name': 'EFI', 'type': 'EFI', 'size': '524288000B', 'format': 'fat',
             'copy_firmware': True, 'copy_installer_data': True},
            {'name': 'Root', 'type': 'Linux', 'size': f'{root_bytes}B',
             'expand': True, 'image': 'root.ext4'},
        ],
        'payloads': {'bootargs': bootargs, **{
            name: {'file': file, 'sha256': sha(path)} for name, (file, path) in parts.items()}},
    }

    (out / 'os').mkdir()
    package = out / 'os' / PACKAGE
    # ZIP dates start at 1980.
    with zipfile.ZipFile(package, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=1,
                         allowZip64=True, strict_timestamps=False) as archive:
        archive.write(args.root_image, 'root.ext4')
        for file, path in parts.values():
            archive.write(path, file)
    with zipfile.ZipFile(package) as archive:
        require(archive.testzip() is None, 'ZIP CRC failure')

    os.environ['REPO_BASE'] = str(out)
    installer = osinstall.OSInstaller(None, {'os_list': [entry]}, entry)
    installer.load_package()
    require(installer.payloads is not None, 'the installer did not read the boot payloads')

    # firn-boot must rewrite the installer's boot.bin unchanged.
    firmware = stand_in_firmware()
    firn_boot.check_firmware(firmware)
    bootbin = payloads.build(installer.payloads, bootargs, firmware)
    loaded = installer.payloads
    again, _ = firn_boot.compose(bootbin, loaded['m1n1'], loaded['kernel'], loaded['dtb'],
                                 loaded['initramfs'], params, args.init)
    require(again == bootbin, 'firn-boot would not reproduce the installer boot.bin')

    shutil.copyfile(Path(args.installer, 'installer.tar.gz'), out / 'installer.tar.gz')
    shutil.copytree(Path(args.installer, 'notices'), out / 'notices')
    for name, source, mode in (('Install.command', args.install_command, 0o755),
                               ('preflight.command', args.preflight, 0o755),
                               ('START-HERE.md', args.start_here, 0o644),
                               ('GUIDE.md', args.guide, 0o644)):
        shutil.copyfile(source, out / name)
        os.chmod(out / name, mode)
    (out / 'installer_data.json').write_text(json.dumps({'os_list': [entry]}, indent=2, sort_keys=True) + '\n')

    report = json.dumps({'bootargs': bootargs, 'bootargs_length': len(bootargs), 'root_bytes': root_bytes,
                         'package_sha256': sha(package),
                         'checks': ['OSInstaller.load_package', 'payloads.read', 'payloads.build',
                                    'firn-boot reproduces the installer boot.bin']},
                        indent=2) + '\n'
    (out / 'BUILD-REPORT.json').write_text(report)

    files = sorted(p.relative_to(out).as_posix() for p in out.rglob('*') if p.is_file())
    (out / 'SHA256SUMS').write_text(''.join(f'{sha(out / name)}  {name}\n' for name in files))
    print(report, end='')


if __name__ == '__main__':
    main()
