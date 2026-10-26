"""Offline tests for m4-nix-boot against synthetic boot.bin files.

When M4BOOT_PY names the installer's src/m4boot.py, the contract tests also
build boot.bin with the installer's own compose() and read it back.
"""
import gzip
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import struct
import tempfile
import unittest
from contextlib import redirect_stdout, redirect_stderr

SPEC = importlib.util.spec_from_file_location('m4_nix_boot', Path(__file__).with_name('m4-nix-boot.py'))
boot = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(boot)

INSTALLER = None
if os.environ.get('M4BOOT_PY'):
    spec = importlib.util.spec_from_file_location('m4boot', os.environ['M4BOOT_PY'])
    INSTALLER = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(INSTALLER)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def fdt(extra=b''):
    """A minimal valid FDT whose strings carry the board name."""
    strings = b'apple,j713\0' + extra
    strings += b'\0' * (-len(strings) % 4)
    structure = struct.pack('>II', 1, 0) + struct.pack('>II', 2, 9)
    rsv = 40
    off_struct = rsv + 16
    off_strings = off_struct + len(structure)
    total = off_strings + len(strings)
    header = struct.pack('>10I', 0xd00dfeed, total, off_struct, off_strings, rsv, 17, 16, 0,
                         len(strings), len(structure))
    return header + b'\0' * 16 + structure + strings


def cpio(entries):
    """A newc archive, written the way the kernel reads it."""
    out = bytearray()
    for ino, (name, mode, body) in enumerate(list(entries) + [('TRAILER!!!', 0, b'')]):
        encoded = name.encode() + b'\0'
        fields = (ino, mode, 0, 0, 1, 0, len(body), 0, 0, 0, 0, len(encoded), 0)
        out += b'070701' + b''.join(b'%08X' % value for value in fields) + encoded
        out += bytes(-len(out) % 4)
        out += body
        out += bytes(-len(out) % 4)
    return bytes(out)


LOADER = b'M1N1-STAGE2' * 64
KERNEL = gzip.compress(b'kernel image', mtime=0)
NEW_KERNEL = gzip.compress(b'nixos kernel image', mtime=0)
DTB = fdt(b'old')
NEW_DTB = fdt(b'new')
FIRMWARE = cpio([('vendorfw', 0o40755, b''),
                 ('vendorfw/.vendorfw.manifest', 0o100644, b'manifest\n'),
                 ('vendorfw/brcm', 0o40755, b''),
                 ('vendorfw/brcm/fw.bin', 0o100644, b'\x01\x02\x03')])
INITRD = gzip.compress(cpio([('init', 0o100755, b'#!/bin/sh\n')]), mtime=0)
NEW_INITRD = gzip.compress(cpio([('init', 0o100755, b'nixos stage 1\n')]), mtime=0)
QUALIFIED = ('maxcpus=10 idle=nop panic=0 console=tty0 fbcon=nodefer loglevel=4 log_buf_len=1M '
             'm4trace_hit=999 dockchannel_hid.m4_power_v2=1 pcie_apple.m4_link_diag=1 '
             'pcie_apple.m4_keep_clocks=1 dockchannel_hid.m4_afe_action=1')
NIXOS_ARGS = QUALIFIED.split() + ['root=fstab', 'loglevel=4']


def installed(loader=LOADER, args=QUALIFIED + ' init=/nix/store/a-nixos-system/init',
              kernel=KERNEL, dtb=DTB, initrd=INITRD, firmware=FIRMWARE):
    """boot.bin as the installer writes it (src/m4boot.py compose)."""
    initramfs = initrd + bytes(-len(initrd) % 4) + firmware
    return boot.join({'loader': loader, 'bootargs': boot.BOOTARGS + args.encode() + b'\n',
                      'kernel': kernel, 'dtb': dtb, 'initramfs': initramfs})


class Pinned(unittest.TestCase):
    def setUp(self):
        self.saved = boot.KERNELS, boot.DTBS, boot.LOADERS
        boot.KERNELS = {sha(NEW_KERNEL): 'test kernel'}
        boot.DTBS = {sha(NEW_DTB): 'test dtb'}
        boot.LOADERS = {sha(LOADER): 'test loader'}

    def tearDown(self):
        boot.KERNELS, boot.DTBS, boot.LOADERS = self.saved

    def compose(self, current=None, **overrides):
        values = dict(current=installed() if current is None else current, kernel=NEW_KERNEL,
                      dtb=NEW_DTB, initrd=NEW_INITRD, args=NIXOS_ARGS,
                      init='/nix/store/x-nixos-system/init')
        values.update(overrides)
        return boot.compose(**values)


class Layout(unittest.TestCase):
    def test_parse_join_round_trip(self):
        data = installed()
        self.assertEqual(boot.join(boot.parse(data)), data)

    def test_trailing_byte_refused(self):
        with self.assertRaises(boot.Refused):
            boot.parse(installed() + b'\0')

    def test_split_installer_initramfs(self):
        initrd, firmware = boot.split_initramfs(boot.parse(installed())['initramfs'])
        self.assertEqual((initrd, firmware), (INITRD, FIRMWARE))
        self.assertIn('vendorfw/brcm/fw.bin', boot.check_firmware(firmware))

    def test_firmware_without_manifest_refused(self):
        with self.assertRaisesRegex(boot.Refused, 'vendorfw.manifest'):
            boot.check_firmware(cpio([('vendorfw', 0o40755, b'')]))

    def test_firmware_outside_vendorfw_refused(self):
        with self.assertRaisesRegex(boot.Refused, 'outside'):
            boot.check_firmware(cpio([('vendorfw/.vendorfw.manifest', 0o100644, b'm'),
                                      ('init', 0o100755, b'x')]))

    def test_truncated_firmware_refused(self):
        with self.assertRaises(boot.Refused):
            boot.split_initramfs(INITRD + bytes(-len(INITRD) % 4) + FIRMWARE[:-200])


class Compose(Pinned):
    def test_parts_replaced_loader_and_firmware_kept(self):
        data, _ = self.compose()
        layout = boot.parse(data)
        self.assertEqual(layout['loader'], LOADER)
        self.assertEqual(layout['kernel'], NEW_KERNEL)
        self.assertEqual(layout['dtb'], NEW_DTB)
        self.assertEqual(boot.split_initramfs(layout['initramfs']), (NEW_INITRD, FIRMWARE))

    def test_bootargs_are_the_generation_params(self):
        data, _ = self.compose()
        line = boot.parse(data)['bootargs'].decode()
        self.assertEqual(line, 'chosen.bootargs=' + QUALIFIED +
                         ' root=fstab init=/nix/store/x-nixos-system/init\n')

    def test_missing_hardware_switch_refused(self):
        args = [arg for arg in NIXOS_ARGS if arg != 'dockchannel_hid.m4_power_v2=1']
        with self.assertRaisesRegex(boot.Refused, 'dockchannel_hid.m4_power_v2=1'):
            self.compose(args=args)

    def test_init_in_params_refused(self):
        with self.assertRaisesRegex(boot.Refused, 'init='):
            self.compose(args=NIXOS_ARGS + ['init=/bin/sh'])

    def test_recompose_is_stable(self):
        first, _ = self.compose()
        self.assertEqual(self.compose(current=first)[0], first)

    def test_new_params_apply_on_recompose(self):
        first, _ = self.compose()
        second, _ = self.compose(current=first, args=NIXOS_ARGS + ['quiet'])
        self.assertIn(b' quiet init=', boot.parse(second)['bootargs'])

    def test_zstd_initrd_refused(self):
        with self.assertRaisesRegex(boot.Refused, 'gzip'):
            self.compose(initrd=b'\x28\xb5\x2f\xfd' + b'zstd frame')

    def test_unpinned_kernel_refused(self):
        with self.assertRaisesRegex(boot.Refused, 'Kernel .* is not pinned'):
            self.compose(kernel=KERNEL)

    def test_unpinned_dtb_refused(self):
        with self.assertRaisesRegex(boot.Refused, 'Devicetree .* is not pinned'):
            self.compose(dtb=DTB)

    def test_unknown_loader_refused_unless_allowed(self):
        other = b'OTHER-LOADER' * 8
        with self.assertRaisesRegex(boot.Refused, 'not one this tool knows'):
            self.compose(current=installed(loader=other))
        data, _ = self.compose(current=installed(loader=other), allowed_loaders=(sha(other),))
        self.assertEqual(boot.parse(data)['loader'], other)

    def test_refused_loader_refused_even_if_allowed(self):
        backlight = b'BACKLIGHT' * 8
        boot.REFUSED_LOADERS[sha(backlight)] = 'backlight stage 2'
        try:
            with self.assertRaisesRegex(boot.Refused, 'backlight'):
                self.compose(current=installed(loader=backlight), allowed_loaders=(sha(backlight),))
        finally:
            del boot.REFUSED_LOADERS[sha(backlight)]

    def test_overlong_bootargs_refused(self):
        with self.assertRaisesRegex(boot.Refused, 'exceed'):
            self.compose(args=NIXOS_ARGS + ['x' * 1100])


@unittest.skipIf(INSTALLER is None, 'M4BOOT_PY is not set')
class InstallerContract(Pinned):
    """boot.bin from the installer's own compose() must read back and recompose."""

    def installer_bootbin(self, initrd=INITRD):
        parts = {'loader': LOADER, 'kernel': KERNEL, 'dtb': DTB, 'initramfs': initrd}
        return INSTALLER.compose(parts, QUALIFIED + ' init=/nix/store/a-nixos-system/init', FIRMWARE)

    def test_installer_output_parses_and_splits(self):
        data = self.installer_bootbin()
        self.assertEqual(data, installed())
        layout = boot.parse(data)
        self.assertEqual(boot.split_initramfs(layout['initramfs']), (INITRD, FIRMWARE))

    def test_recompose_matches_what_the_installer_would_write(self):
        data, _ = self.compose(current=self.installer_bootbin())
        parts = {'loader': LOADER, 'kernel': NEW_KERNEL, 'dtb': NEW_DTB, 'initramfs': NEW_INITRD}
        expected = INSTALLER.compose(parts, QUALIFIED + ' root=fstab init=/nix/store/x-nixos-system/init',
                                     FIRMWARE)
        self.assertEqual(data, expected)


class Install(Pinned):
    def setUp(self):
        super().setUp()
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.efi = root / 'efi'
        (self.efi / 'omarchy').mkdir(parents=True)
        self.boot = self.efi / 'omarchy' / 'boot.bin'
        self.boot.write_bytes(installed())
        self.toplevel = root / 'system'
        (self.toplevel / 'dtbs' / 'apple').mkdir(parents=True)
        (self.toplevel / 'kernel').write_bytes(NEW_KERNEL)
        (self.toplevel / 'dtbs' / 'apple' / 'm4-nix-j713.dtb').write_bytes(NEW_DTB)
        (self.toplevel / 'initrd').write_bytes(NEW_INITRD)
        (self.toplevel / 'kernel-params').write_text(' '.join(NIXOS_ARGS))
        # The generation is reached through a profile link, as NixOS passes it.
        self.saved_store = boot.STORE
        boot.STORE = str(root.resolve()) + '/'
        self.link = root / 'system-1-link'
        self.link.symlink_to(self.toplevel)
        self.sys = root / 'sys'
        (self.sys / 'proc' / 'device-tree').mkdir(parents=True)
        (self.sys / 'proc' / 'device-tree' / 'compatible').write_bytes(b'apple,j713\0apple,t8132\0apple,arm-platform\0')

    def tearDown(self):
        boot.STORE = self.saved_store
        self.tmp.cleanup()
        super().tearDown()

    def run_tool(self, *extra):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            status = boot.main(['install', str(self.link), '--efi', str(self.efi),
                                '--sys-root', str(self.sys), *extra])
        return status, out.getvalue(), err.getvalue()

    def test_dry_run_writes_nothing(self):
        before = self.boot.read_bytes()
        status, out, _ = self.run_tool()
        self.assertEqual(status, 0)
        self.assertIn('Dry run', out)
        self.assertEqual(self.boot.read_bytes(), before)
        self.assertEqual(sorted(os.listdir(self.efi / 'omarchy')), ['boot.bin'])

    def test_apply_keeps_original_once_and_boots_store_path(self):
        original = self.boot.read_bytes()
        self.assertEqual(self.run_tool('--apply')[0], 0)
        self.assertEqual((self.efi / 'omarchy' / 'boot.bin.original').read_bytes(), original)
        line = boot.parse(self.boot.read_bytes())['bootargs'].decode()
        self.assertIn('init=' + str(self.toplevel.resolve() / 'init'), line)
        (self.toplevel / 'kernel-params').write_text(' '.join(NIXOS_ARGS + ['quiet']))
        first = self.boot.read_bytes()
        self.assertEqual(self.run_tool('--apply')[0], 0)
        self.assertEqual((self.efi / 'omarchy' / 'boot.bin.original').read_bytes(), original)
        self.assertEqual((self.efi / 'omarchy' / 'boot.bin.previous').read_bytes(), first)

    def test_other_board_refused_before_writing(self):
        (self.sys / 'proc' / 'device-tree' / 'compatible').write_bytes(b'apple,j715\0apple,t8132\0')
        before = self.boot.read_bytes()
        status, _, err = self.run_tool('--apply')
        self.assertEqual(status, 1)
        self.assertIn('apple,j713', err)
        self.assertEqual(self.boot.read_bytes(), before)
        self.assertFalse((self.efi / 'omarchy' / 'boot.bin.original').exists())

    def test_other_board_refused_even_when_already_current(self):
        self.assertEqual(self.run_tool('--apply')[0], 0)
        (self.sys / 'proc' / 'device-tree' / 'compatible').write_bytes(b'linux,dummy-virt\0')
        status, _, err = self.run_tool('--apply')
        self.assertEqual(status, 1)
        self.assertIn('apple,j713', err)

    def test_loader_from_other_file(self):
        other = b'OTHER-LOADER' * 8
        source = self.efi / 'omarchy' / 'older.bin'
        source.write_bytes(installed(loader=other))
        status, _, _ = self.run_tool('--apply', '--loader-from', str(source), '--allow-loader', sha(other))
        self.assertEqual(status, 0)
        self.assertEqual(boot.parse(self.boot.read_bytes())['loader'], other)

    def test_not_a_store_path_refused(self):
        self.link.unlink()
        self.link.symlink_to('/tmp')
        status, _, err = self.run_tool()
        self.assertEqual(status, 1)
        self.assertIn('not a NixOS generation', err)


if __name__ == '__main__':
    unittest.main()
