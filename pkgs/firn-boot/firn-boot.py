#!/usr/bin/env python3
"""Write the J713 m1n1 boot.bin for a NixOS generation.

boot.bin is the file the installer writes to <ESP>/m1n1/boot.bin for an OS
booted by m1n1 stage 2 directly (its payloads.py). Its layout:

    m1n1 stage 2
    chosen.bootargs=<one printable line>\\n
    gzip kernel
    flattened devicetree
    m1n1_initramfs <u32 LE length> <gzip initrd> <zero pad to 4> <firmware cpio>

The firmware cpio holds the Apple firmware the installer collected on this Mac,
under /vendorfw. m1n1 stage 1 appends its variables to the image at boot, so
they are not in the file.

This keeps the installed firmware and writes everything else from the
generation: m1n1 stage 2, kernel, devicetree, initrd and kernel parameters.
The parameters must keep the kernel's hardware switches.

Nothing is written without --apply. The first boot.bin this tool replaces (the
installer's) is kept as boot.bin.original and never overwritten; every later
apply keeps the replaced file as boot.bin.previous.
"""
import argparse
import hashlib
import os
from pathlib import Path
import struct
import sys
import zlib

# Kernel parameters the J713 does not boot reliably without; a generation
# that drops one is refused. WFIT in __delay() stops the M4 at EL2.
REQUIRED_ARGS = (
    'maxcpus=10',
    'idle=nop',
    'arm64.nowfxt',
)
BOARD = b'apple,j713'
BOOTARGS = b'chosen.bootargs='
GZIP = b'\x1f\x8b\x08'
FDT_MAGIC = b'\xd0\x0d\xfe\xed'
INITRAMFS = b'm1n1_initramfs'
MAX_BOOTARGS = 1024
# The installer's limits (payloads.py).
LIMITS = {'loader': 4 << 20, 'kernel': 64 << 20, 'dtb': 2 << 20, 'initrd': 128 << 20,
          'firmware': 128 << 20}
FIRMWARE_DIR = 'vendorfw'
FIRMWARE_MANIFEST = 'vendorfw/.vendorfw.manifest'
CPIO_MAGIC = b'070701'
TRAILER = 'TRAILER!!!'
MARGIN = 1 << 20
STORE = '/nix/store/'
BOOT_DIR = 'm1n1'
DTB = 'dtbs/apple/t8132-j713.dtb'
ORIGINAL = 'boot.bin.original'
PREVIOUS = 'boot.bin.previous'


class Refused(Exception):
    pass


def require(condition, message):
    if not condition:
        raise Refused(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def gzip_end(data, start):
    stream = zlib.decompressobj(31)
    try:
        stream.decompress(memoryview(data)[start:])
    except zlib.error:
        return None
    if not stream.eof:
        return None
    return len(data) - len(stream.unused_data)


def fdt_size(data, offset):
    if data[offset:offset + 4] != FDT_MAGIC or offset + 40 > len(data):
        return None
    total, structure, strings, _, version, last = struct.unpack_from('>6I', data, offset + 4)
    if not (40 <= total <= len(data) - offset and version >= 16 and last <= 16 and
            structure < total and strings < total):
        return None
    return total


def parse_at(data, start):
    end = data.find(b'\n', start)
    if start == 0 or end < 0:
        return None
    line = data[start:end + 1]
    if not all(32 <= byte < 127 for byte in line[:-1]):
        return None
    kernel = end + 1
    if data[kernel:kernel + 3] != GZIP:
        return None
    dtb = gzip_end(data, kernel)
    if dtb is None:
        return None
    size = fdt_size(data, dtb)
    if size is None:
        return None
    tag = dtb + size
    if data[tag:tag + len(INITRAMFS)] != INITRAMFS or tag + len(INITRAMFS) + 4 > len(data):
        return None
    length, = struct.unpack_from('<I', data, tag + len(INITRAMFS))
    body = tag + len(INITRAMFS) + 4
    if body + length != len(data):
        return None
    return {'loader': data[:start], 'bootargs': line, 'kernel': data[kernel:dtb],
            'dtb': data[dtb:tag], 'initramfs': data[body:]}


def parse(data):
    """Split boot.bin; exactly one layout must consume the whole file."""
    found, position = [], data.find(BOOTARGS)
    while position >= 0:
        layout = parse_at(data, position)
        if layout is not None:
            found.append(layout)
        position = data.find(BOOTARGS, position + 1)
    require(len(found) == 1, 'boot.bin does not have the expected loader, boot arguments, '
            'kernel, devicetree and initramfs layout')
    return found[0]


def join(layout):
    initramfs = layout['initramfs']
    return b''.join((layout['loader'], layout['bootargs'], layout['kernel'], layout['dtb'],
                     INITRAMFS, struct.pack('<I', len(initramfs)), initramfs))


def split_initramfs(initramfs):
    """Return (gzip initrd, firmware cpio) from the installer's initramfs layout."""
    require(initramfs[:3] == GZIP, 'The initramfs does not start with a gzip initrd')
    end = gzip_end(initramfs, 0)
    require(end is not None, 'The initrd is not one complete gzip member')
    start = end + (-end % 4)
    require(initramfs[end:start] == b'\0' * (start - end), 'Unexpected bytes after the initrd')
    firmware = initramfs[start:]
    require(firmware.startswith(CPIO_MAGIC) and (TRAILER + '\0').encode() in firmware[-124:],
            'The firmware after the initrd is not one complete newc archive')
    return initramfs[:end], firmware


def cpio_names(data):
    """Names in one newc archive, checking its structure to the trailer."""
    names, position = [], 0
    while True:
        require(data[position:position + 6] == CPIO_MAGIC, 'Corrupt firmware cpio')
        require(position + 110 <= len(data), 'Truncated firmware cpio header')
        fields = [int(data[position + 6 + 8 * i:position + 14 + 8 * i], 16) for i in range(13)]
        filesize, namesize = fields[6], fields[11]
        start = position + 110
        require(namesize >= 1 and start + namesize <= len(data), 'Truncated firmware cpio name')
        name = data[start:start + namesize - 1].decode('utf-8', 'surrogateescape')
        body = (start + namesize + 3) & ~3
        position = (body + filesize + 3) & ~3
        require(body + filesize <= len(data), 'Truncated firmware cpio body')
        if name == TRAILER:
            require(data[position:].strip(b'\0') == b'', 'Data after the firmware cpio trailer')
            return names
        names.append(name.lstrip('/'))


def check_firmware(firmware):
    names = cpio_names(firmware)
    require(FIRMWARE_MANIFEST in names, 'The firmware archive has no ' + FIRMWARE_MANIFEST)
    require(all(name == FIRMWARE_DIR or name.startswith(FIRMWARE_DIR + '/') for name in names),
            'The firmware archive has files outside /' + FIRMWARE_DIR)
    return names


def bootargs_line(args, init):
    require(not any(arg.startswith('init=') for arg in args), 'Kernel parameters already set init=')
    missing = [arg for arg in REQUIRED_ARGS if arg not in args]
    require(not missing, "Kernel parameters lack the kernel's hardware switches: " + ' '.join(missing))
    unique = list(dict.fromkeys(args))
    line = BOOTARGS + ' '.join(unique + ['init=' + init]).encode() + b'\n'
    require(len(line) - len(BOOTARGS) - 1 <= MAX_BOOTARGS,
            f'Boot arguments exceed {MAX_BOOTARGS} characters')
    require(all(32 <= byte < 127 for byte in line[:-1]), 'Boot arguments must be printable ASCII')
    return line


def compose(current, loader, kernel, dtb, initrd, args, init):
    """Return (new boot.bin bytes, report lines): the generation's parts with
    the firmware from the current boot.bin."""
    _, firmware = split_initramfs(parse(current)['initramfs'])
    names = check_firmware(firmware)
    require(len(firmware) <= LIMITS['firmware'], 'The firmware archive is too large')

    require(0 < len(loader) <= LIMITS['loader'], 'm1n1 stage 2 is empty or too large')
    require(kernel[:3] == GZIP and gzip_end(kernel, 0) == len(kernel), 'Kernel is not one gzip member')
    require(len(kernel) <= LIMITS['kernel'], 'The kernel is larger than the installer allows')
    require(fdt_size(dtb, 0) == len(dtb), 'Devicetree is not one flattened devicetree')
    require(len(dtb) <= LIMITS['dtb'], 'The devicetree is larger than the installer allows')
    require(BOARD + b'\0' in dtb, 'Devicetree is not for apple,j713')
    require(initrd[:3] == GZIP and gzip_end(initrd, 0) == len(initrd),
            'The initrd must be one gzip member (boot.initrd.compressor = "gzip")')
    require(len(initrd) <= LIMITS['initrd'], 'The initrd is larger than the installer allows')

    initramfs = initrd + bytes(-len(initrd) % 4) + firmware
    new = {'loader': loader, 'bootargs': bootargs_line(args, init), 'kernel': kernel,
           'dtb': dtb, 'initramfs': initramfs}
    data = join(new)
    check = parse(data)
    require(all(check[name] == new[name] for name in new), 'Composed boot.bin does not read back')
    require(split_initramfs(check['initramfs']) == (initrd, firmware), 'Composed initramfs does not split back')

    report = [
        f'loader     {sha(loader)}  {len(loader)} bytes',
        f'kernel     {sha(kernel)}  {len(kernel)} bytes',
        f'devicetree {sha(dtb)}  {len(dtb)} bytes',
        f'initrd     {sha(initrd)}  {len(initrd)} bytes',
        f'firmware   {len(names)} entries, {len(firmware)} bytes, kept from the installed boot.bin',
        'bootargs   ' + new['bootargs'][len(BOOTARGS):-1].decode(),
    ]
    return data, report


def temporary(path):
    return path.with_name(path.name + '.firn-tmp')


def write_file(path, data):
    with open(temporary(path), 'wb') as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary(path), path)


def free_space(path):
    stat = os.statvfs(path)
    return stat.f_bavail * stat.f_frsize


def megabytes(size):
    return -(-size // 1000000)


def sync_dir(path):
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def check_board(sys_root):
    compatible = Path(sys_root, 'proc/device-tree/compatible')
    require(compatible.is_file(), 'Cannot read the running board from ' + str(compatible))
    require(BOARD + b'\0' in compatible.read_bytes() + b'\0',
            'This is not a 13-inch M4 MacBook Air (apple,j713)')


def read_toplevel(toplevel):
    # A profile link (system-N-link) must not end up in init=; boot the store path.
    toplevel = Path(os.path.realpath(toplevel))
    require(str(toplevel).startswith(STORE), f'{toplevel} is not a NixOS generation in {STORE}')
    require((toplevel / 'm1n1.bin').is_file(), f'{toplevel} has no m1n1.bin')
    return {
        'loader': (toplevel / 'm1n1.bin').read_bytes(),
        'kernel': (toplevel / 'kernel').read_bytes(),
        'dtb': (toplevel / DTB).read_bytes(),
        'initrd': (toplevel / 'initrd').read_bytes(),
        'args': (toplevel / 'kernel-params').read_text().split(),
        'init': str(toplevel / 'init'),
    }


def install(args):
    if args.apply:
        check_board(args.sys_root)
    boot = Path(args.efi, BOOT_DIR, 'boot.bin')
    require(boot.is_file() and not boot.is_symlink(), f'{boot} is missing (is the ESP mounted at {args.efi}?)')
    current = boot.read_bytes()
    data, report = compose(current, **read_toplevel(args.toplevel))
    print('\n'.join(report))
    if data == current:
        print('boot.bin is already this generation')
        return
    if not args.apply:
        print(f'Dry run: would write {len(data)} bytes to {boot}. Pass --apply to write it.')
        return

    original = boot.with_name(ORIGINAL)
    previous = boot.with_name(PREVIOUS)
    for path in (boot, original, previous):
        temporary(path).unlink(missing_ok=True)
    # FAT has no links, so every kept file is a full copy. On the first apply
    # the replaced file is the installer's, kept as boot.bin.original, so
    # boot.bin.previous is written from the second apply on, after the old one
    # is removed; boot.bin.original stays the fallback meanwhile. The new
    # boot.bin is written beside the current one before it replaces it.
    first = not original.exists()
    freed = 0 if first or not previous.exists() else previous.stat().st_size
    need = len(current) + len(data) + MARGIN
    free = free_space(boot.parent) + freed
    require(free >= need, f'Not enough free space on the EFI partition: '
            f'{megabytes(need)} MB needed, {megabytes(free)} MB free')
    if first:
        write_file(original, current)
        print(f'Kept the installed boot.bin as {original}')
    else:
        previous.unlink(missing_ok=True)
        write_file(previous, current)
    write_file(boot, data)
    sync_dir(boot.parent)
    require(boot.read_bytes() == data, 'boot.bin did not read back after writing')
    print(f'Wrote {boot}; the replaced file is {original if first else previous}')


def inspect(args):
    layout = parse(Path(args.file).read_bytes())
    print(f'loader     {sha(layout["loader"])}  {len(layout["loader"])} bytes')
    print(f'kernel     {sha(layout["kernel"])}  {len(layout["kernel"])} bytes')
    print(f'devicetree {sha(layout["dtb"])}  {len(layout["dtb"])} bytes')
    print('bootargs   ' + layout['bootargs'][len(BOOTARGS):-1].decode())
    try:
        initrd, firmware = split_initramfs(layout['initramfs'])
        print(f'initrd     {sha(initrd)}  {len(initrd)} bytes')
        print(f'firmware   {len(check_firmware(firmware))} entries under /{FIRMWARE_DIR}')
    except Refused as error:
        print(f'initramfs  {error}')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    commands = parser.add_subparsers(dest='command', required=True)
    show = commands.add_parser('inspect', help='describe a boot.bin')
    show.add_argument('file')
    show.set_defaults(run=inspect)
    put = commands.add_parser('install', help='compose boot.bin for a NixOS generation')
    put.add_argument('toplevel', help='the generation (/nix/var/nix/profiles/system-N-link)')
    put.add_argument('--efi', default='/boot/efi', help='ESP mount point (default /boot/efi)')
    put.add_argument('--apply', action='store_true', help='write boot.bin (default: dry run)')
    put.add_argument('--sys-root', default='/', help=argparse.SUPPRESS)
    put.set_defaults(run=install)
    args = parser.parse_args(argv)
    try:
        args.run(args)
    except (Refused, OSError) as error:
        print(f'firn-boot: refused: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
