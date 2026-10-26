#!/usr/bin/env python3
"""Assemble the NixOS installer kit for the J713 installer and validate it.

The kit is the update 4 installer bundle, unchanged, with our installer_data.json
and OS package. Before writing anything final, the package is checked with the
installer's own code (osinstall.OSInstaller root checks and m4boot.read_parts),
and the boot.bin the installer would compose is read back with m4-nix-boot.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tarfile
import tempfile
import zipfile


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


def main():
    parser = argparse.ArgumentParser()
    for name in ('installer-kit', 'root-image', 'loader', 'kernel', 'dtb', 'initrd',
                 'kernel-params', 'init', 'rootfs-uuid', 'os-name', 'nix-boot',
                 'install-command', 'preflight', 'start-here', 'guide', 'out'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir()

    nix_boot = load('m4_nix_boot', args.nix_boot)
    with tempfile.TemporaryDirectory() as scratch:
        bundle = Path(scratch, 'installer')
        bundle.mkdir()
        with tarfile.open(Path(args.installer_kit, 'installer-macos.tar.gz')) as archive:
            for member in ('./m4boot.py', './osinstall.py', './util.py', './urlcache.py', './m1n1.py'):
                archive.extract(member, bundle, filter='data')
        sys.path.insert(0, str(bundle))
        m4boot = importlib.import_module('m4boot')
        osinstall = importlib.import_module('osinstall')

        params = Path(args.kernel_params).read_text().split()
        line = nix_boot.bootargs_line(params, args.init)
        bootargs = line[len(nix_boot.BOOTARGS):-1].decode()

        boot_files = {
            'loader': ('boot/loader.bin', args.loader),
            'kernel': ('boot/Image.gz', args.kernel),
            'dtb': ('boot/portable.dtb', args.dtb),
            'initramfs': ('boot/initramfs.cpio.gz', args.initrd),
        }
        root_bytes = os.path.getsize(args.root_image)
        require(root_bytes % (1 << 20) == 0, 'root image is not a whole number of MiB')
        package_name = 'nixos-j713.zip'
        entry = {
            'boot_object': 'm1n1.bin',
            'default_os_name': args.os_name,
            'expert': True,
            'm4_boot': {'bootargs': bootargs, **{
                part: {'file': name, 'sha256': sha(path)} for part, (name, path) in boot_files.items()}},
            'name': args.os_name + ' (experimental J713, minimal-risk profile)',
            'next_object': 'omarchy/boot.bin',
            'package': package_name,
            'partitions': [
                {'copy_firmware': True, 'copy_installer_data': True, 'format': 'fat', 'name': 'EFI',
                 'size': '524288000B', 'type': 'EFI'},
                {'expand': True, 'image': 'root.ext4', 'name': 'Root', 'rootfs_uuid': args.rootfs_uuid,
                 'size': f'{root_bytes}B', 'type': '0fc63daf-8483-4772-8e79-3d69d8477de4'},
            ],
            'supported_fw': ['26.5.1'],
        }

        (out / 'os').mkdir()
        package = out / 'os' / package_name
        # Store paths are dated 1970; ZIP starts at 1980, so dates are clamped.
        with zipfile.ZipFile(package, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=1,
                             allowZip64=True, strict_timestamps=False) as archive:
            archive.write(args.root_image, 'root.ext4')
            for name, path in boot_files.values():
                archive.write(path, name)

        # The installer's own checks, as OSInstaller.__init__ and load_package run them.
        installer = osinstall.OSInstaller.__new__(osinstall.OSInstaller)
        installer.template = entry
        installer.root_part_index = None
        installer.rootfs_uuid = None
        installer.validate_root_template()
        m4boot.validate_spec(entry['m4_boot'])
        with zipfile.ZipFile(package) as archive:
            require(archive.testzip() is None, 'ZIP CRC failure')
            installer.pkg = archive
            installer.validate_root_image()
            parts = m4boot.read_parts(archive, entry['m4_boot'])

        # The boot.bin the installer will write, with a stand-in firmware archive,
        # must be one m4-nix-boot reads and would rewrite to the same bytes.
        firmware = nix_boot_firmware(nix_boot)
        bootbin = m4boot.compose(parts, bootargs, firmware)
        layout = nix_boot.parse(bootbin)
        require(nix_boot.sha(layout['loader']) in nix_boot.LOADERS, 'loader is not pinned in m4-nix-boot')
        require(nix_boot.split_initramfs(layout['initramfs']) == (parts['initramfs'], firmware),
                'installer initramfs does not split back')
        again, _ = nix_boot.compose(bootbin, parts['kernel'], parts['dtb'], parts['initramfs'],
                                    params, args.init)
        require(again == bootbin, 'm4-nix-boot would not reproduce the installer boot.bin')

    shutil.copyfile(Path(args.installer_kit, 'installer-macos.tar.gz'), out / 'installer-macos.tar.gz')
    shutil.copytree(Path(args.installer_kit, 'notices'), out / 'notices')
    shutil.copyfile(args.install_command, out / 'Install.command')
    os.chmod(out / 'Install.command', 0o755)
    shutil.copyfile(args.preflight, out / 'preflight.command')
    os.chmod(out / 'preflight.command', 0o755)
    shutil.copyfile(args.start_here, out / 'START-HERE.md')
    shutil.copyfile(args.guide, out / 'GUIDE.md')
    (out / 'installer_data.json').write_text(json.dumps({'os_list': [entry]}, indent=2, sort_keys=True) + '\n')
    report = json.dumps({'bootargs': bootargs, 'bootargs_length': len(bootargs), 'root_bytes': root_bytes,
                         'package_sha256': sha(package),
                         'checks': ['OSInstaller.validate_root_template', 'OSInstaller.validate_root_image',
                                    'm4boot.validate_spec', 'm4boot.read_parts',
                                    'm4-nix-boot reproduces the installer boot.bin']},
                        indent=2) + '\n'
    (out / 'BUILD-REPORT.json').write_text(report)

    files = sorted(p.relative_to(out).as_posix() for p in out.rglob('*') if p.is_file())
    (out / 'SHA256SUMS').write_text(''.join(f'{sha(out / name)}  {name}\n' for name in files))
    print(report, end='')


def nix_boot_firmware(nix_boot):
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
    firmware = bytes(out)
    nix_boot.check_firmware(firmware)
    return firmware


if __name__ == '__main__':
    main()
