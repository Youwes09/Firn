#!/usr/bin/env python3
"""Print how two flattened devicetrees differ, one line per difference:

    only in A: <node>        only in B: <node>
    <node>: <property>

Nodes are matched by path. Phandle values are compared by the path of the node
they point to, so renumbered phandles are not differences. An absent status
equals "okay"."""
import struct
import sys


def parse(path):
    with open(path, 'rb') as handle:
        data = handle.read()
    magic, _, off_struct, off_strings = struct.unpack_from('>IIII', data, 0)
    if magic != 0xd00dfeed:
        sys.exit(f'{path} is not a flattened devicetree')
    nodes, stack, pos = {}, [], off_struct
    while True:
        (tag,) = struct.unpack_from('>I', data, pos)
        pos += 4
        if tag == 1:  # FDT_BEGIN_NODE
            end = data.index(b'\0', pos)
            stack.append(data[pos:end].decode())
            pos = (end + 4) & ~3
            nodes['/' + '/'.join(stack[1:])] = {}
        elif tag == 2:  # FDT_END_NODE
            stack.pop()
        elif tag == 3:  # FDT_PROP
            size, name_offset = struct.unpack_from('>II', data, pos)
            pos += 8
            start = off_strings + name_offset
            name = data[start:data.index(b'\0', start)].decode()
            nodes['/' + '/'.join(stack[1:])][name] = data[pos:pos + size]
            pos = (pos + size + 3) & ~3
        elif tag == 9:  # FDT_END
            return nodes


def phandles(nodes):
    return {struct.unpack('>I', props['phandle'])[0]: path
            for path, props in nodes.items() if 'phandle' in props}


def same(x, y, pa, pb):
    if x == y:
        return True
    if x is None or y is None or len(x) != len(y) or len(x) % 4:
        return False
    cells = zip(struct.unpack(f'>{len(x) // 4}I', x), struct.unpack(f'>{len(y) // 4}I', y))
    return all(u == v or (u in pa and v in pb and pa[u] == pb[v]) for u, v in cells)


def differences(a, b):
    pa, pb = phandles(a), phandles(b)
    for path in sorted(set(a) | set(b)):
        if path.startswith(('/__symbols__', '/__fixups__', '/__local_fixups__')):
            continue
        if path not in b:
            yield f'only in A: {path}'
        elif path not in a:
            yield f'only in B: {path}'
        else:
            for prop in sorted((set(a[path]) | set(b[path])) - {'phandle', 'linux,phandle'}):
                x, y = a[path].get(prop), b[path].get(prop)
                if prop == 'status':
                    x, y = x or b'okay\0', y or b'okay\0'
                if not same(x, y, pa, pb):
                    yield f'{path}: {prop}'


if __name__ == '__main__':
    for line in differences(parse(sys.argv[1]), parse(sys.argv[2])):
        print(line)
