#!/usr/bin/env python3
"""Fetch one member of a ZIP split into release parts, using HTTP range requests.

Usage: fetch-zip-member.py MEMBER OUTPUT URL:SIZE [URL:SIZE ...]

The parts concatenate to one ZIP64 archive. Only the central directory and the
member are downloaded; the caller pins the result's hash.
"""
import os
import struct
import ssl
import sys
import urllib.request
import zlib

CONTEXT = ssl.create_default_context(cafile=os.environ.get('SSL_CERT_FILE'))


def main(member, output, specs):
    parts = []
    for spec in specs:
        url, size = spec.rsplit(':', 1)
        parts.append((url, int(size)))
    total = sum(size for _, size in parts)

    def get(offset, length):
        out, start = b'', 0
        for url, size in parts:
            if offset < start + size and offset + length > start:
                low = max(offset, start) - start
                high = min(offset + length, start + size) - start
                request = urllib.request.Request(url, headers={'Range': f'bytes={low}-{high - 1}'})
                with urllib.request.urlopen(request, timeout=120, context=CONTEXT) as response:
                    out += response.read()
            start += size
        if len(out) != length:
            raise SystemExit(f'short read at {offset}: {len(out)} of {length}')
        return out

    tail = get(total - 65536, 65536)
    locator = tail.rfind(b'PK\x06\x07')
    if locator < 0:
        raise SystemExit('no ZIP64 end of central directory locator')
    record = get(struct.unpack_from('<Q', tail, locator + 8)[0], 56)
    if record[:4] != b'PK\x06\x06':
        raise SystemExit('bad ZIP64 end of central directory record')
    size, offset = struct.unpack_from('<QQ', record, 40)
    directory = get(offset, size)

    position = 0
    while position < len(directory):
        if struct.unpack_from('<I', directory, position)[0] != 0x02014b50:
            raise SystemExit('bad central directory entry')
        method, = struct.unpack_from('<H', directory, position + 10)
        csize, usize = struct.unpack_from('<II', directory, position + 20)
        nlen, elen, clen = struct.unpack_from('<HHH', directory, position + 28)
        local, = struct.unpack_from('<I', directory, position + 42)
        name = directory[position + 46:position + 46 + nlen].decode()
        extra = directory[position + 46 + nlen:position + 46 + nlen + elen]
        position += 46 + nlen + elen + clen
        if name != member:
            continue
        wide, cursor = [], 0
        while cursor < len(extra):
            kind, length = struct.unpack_from('<HH', extra, cursor)
            if kind == 1:
                wide = list(struct.unpack_from('<' + 'Q' * (length // 8), extra, cursor + 4))
            cursor += 4 + length
        if usize == 0xFFFFFFFF:
            usize = wide.pop(0)
        if csize == 0xFFFFFFFF:
            csize = wide.pop(0)
        if local == 0xFFFFFFFF:
            local = wide.pop(0)
        header = get(local, 30)
        if header[:4] != b'PK\x03\x04':
            raise SystemExit('bad local header')
        nlen, elen = struct.unpack_from('<HH', header, 26)
        data = get(local + 30 + nlen + elen, csize)
        if method == 8:
            data = zlib.decompress(data, -15)
        elif method != 0:
            raise SystemExit(f'unsupported compression method {method}')
        if len(data) != usize:
            raise SystemExit('size mismatch')
        with open(output, 'wb') as handle:
            handle.write(data)
        return
    raise SystemExit(f'{member} is not in the archive')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
