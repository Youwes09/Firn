#!/usr/bin/env python3
"""Fetch members of a remote uncompressed tar with HTTP range requests.

Usage: fetch-tar-member.py URL OUTPUT-DIR MEMBER [MEMBER ...]

Walks the 512-byte ustar headers, downloading only headers and the named
members. The caller pins the result's hash.
"""
import os
import ssl
import sys
import urllib.request

CONTEXT = ssl.create_default_context(cafile=os.environ.get('SSL_CERT_FILE'))


def main(url, output, members):
    def get(offset, length):
        request = urllib.request.Request(url, headers={'Range': f'bytes={offset}-{offset + length - 1}'})
        with urllib.request.urlopen(request, timeout=120, context=CONTEXT) as response:
            data = response.read()
        if len(data) != length:
            raise SystemExit(f'short read at {offset}')
        return data

    wanted, offset, long_name = set(members), 0, None
    while wanted:
        header = get(offset, 512)
        if header == bytes(512):
            raise SystemExit('end of archive; missing: ' + ', '.join(sorted(wanted)))
        if header[257:262] != b'ustar':
            raise SystemExit(f'not a ustar header at {offset}')
        size = int(header[124:136].strip(b'\0 ') or b'0', 8)
        kind = header[156:157]
        name = header[0:100].split(b'\0')[0].decode()
        prefix = header[345:500].split(b'\0')[0].decode()
        if prefix:
            name = prefix + '/' + name
        if long_name is not None:
            name, long_name = long_name, None
        data_offset = offset + 512
        if kind == b'L':
            long_name = get(data_offset, size).split(b'\0')[0].decode()
        elif kind in (b'0', b'\0') and name.lstrip('./') in wanted:
            member = name.lstrip('./')
            target = os.path.join(output, member)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, 'wb') as handle:
                handle.write(get(data_offset, size))
            wanted.discard(member)
        offset = data_offset + (size + 511) // 512 * 512


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
