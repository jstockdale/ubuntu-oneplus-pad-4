#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
# Prove the initramfs is self-contained: every ELF inside it must find its
# interpreter and every DT_NEEDED library inside the same archive. This is
# the gate that makes trimming safe — a kept binary linked against a
# deleted library would otherwise only be discovered on a dark panel.
#
# Usage: check-initramfs-closure.sh [initrd]   (default: the rootfs's)
set -euo pipefail

base=${UBUNTU_WORKDIR:-/srv/ubuntu-iceland}
initrd=${1:-$base/rootfs/boot/initrd.img-$(cat "$base/out/kernel-iceland/kernel.release" 2>/dev/null || echo 7.3.0+)}
test -f "$initrd" || { echo "missing $initrd" >&2; exit 1; }

readelf_bin=$(command -v readelf || command -v llvm-readelf) || {
	echo 'need readelf or llvm-readelf (apt install binutils or llvm)' >&2
	exit 1
}

python3 - "$initrd" "$readelf_bin" <<'PYEOF'
import os, subprocess, sys, tempfile

data = open(sys.argv[1], 'rb').read()
readelf = sys.argv[2]

# Collect every entry (name -> content for files, target for symlinks)
# across all segments: plain cpio segments, then the LZ4 main body.
entries, links = {}, {}

def walk(raw):
    k = 0
    while k < len(raw):
        hdr = raw[k:k+110]
        if hdr[:6] not in (b'070701', b'070702'):
            return k
        mode = int(hdr[14:22], 16)
        ns = int(hdr[94:102], 16)
        fs = int(hdr[54:62], 16)
        name = raw[k+110:k+110+ns-1].decode(errors='replace')
        body_at = (k + 110 + ns + 3) // 4 * 4
        k = (body_at + fs + 3) // 4 * 4
        if name == 'TRAILER!!!':
            return k
        body = raw[body_at:body_at+fs]
        if (mode & 0o170000) == 0o120000:
            links[name] = body.decode(errors='replace')
        else:
            entries[name] = body
    return k

i = 0
while i < len(data):
    if data[i:i+6] in (b'070701', b'070702'):
        j = walk(data[i:])
        i += j
        while i < len(data) and data[i:i+1] == b'\x00':
            i += 1
        continue
    if data[i:i+4] == b'\x02\x21\x4c\x18':
        out = subprocess.run(['lz4', '-dc'], input=data[i:],
                             capture_output=True).stdout
        walk(out)
        break
    sys.exit(f'unknown segment magic at {i}: {data[i:i+4].hex()}')

def resolve(path, depth=0):
    """Resolve a path against entries and symlinks (incl. usrmerge dirs)."""
    if depth > 8:
        return None
    path = path.lstrip('/')
    if path in entries:
        return path
    if path in links:
        tgt = links[path]
        if not tgt.startswith('/'):
            tgt = os.path.normpath(os.path.join(os.path.dirname(path), tgt))
        return resolve(tgt, depth+1)
    # walk parent dirs through symlinks (lib -> usr/lib)
    parts = path.split('/')
    for n in range(len(parts)-1, 0, -1):
        prefix = '/'.join(parts[:n])
        if prefix in links:
            tgt = links[prefix]
            if not tgt.startswith('/'):
                tgt = os.path.normpath(
                    os.path.join(os.path.dirname(prefix), tgt))
            return resolve(tgt + '/' + '/'.join(parts[n:]), depth+1)
    return None

libdirs = ['usr/lib/aarch64-linux-gnu', 'lib/aarch64-linux-gnu',
           'usr/lib', 'lib']
elves, dangling = 0, []
with tempfile.TemporaryDirectory() as td:
    for name, body in entries.items():
        if body[:4] != b'\x7fELF':
            continue
        elves += 1
        p = os.path.join(td, 'e')
        open(p, 'wb').write(body)
        dyn = subprocess.run([readelf, '-d', p], capture_output=True,
                             text=True).stdout
        prog = subprocess.run([readelf, '-l', p], capture_output=True,
                              text=True).stdout
        needs = [l.split('[')[1].rstrip(']\n')
                 for l in dyn.splitlines()
                 if ('NEEDED' in l or '(NEEDED)' in l) and '[' in l]
        # Per-binary RUNPATH/RPATH extend the search path: systemd's
        # tools find libsystemd-shared in a systemd/ subdirectory this way.
        extra = []
        for l in dyn.splitlines():
            if ('RUNPATH' in l or 'RPATH' in l) and '[' in l:
                for d in l.split('[')[1].rstrip(']\n').split(':'):
                    d = d.replace('$ORIGIN', os.path.dirname('/' + name))
                    extra.append(d.lstrip('/'))
        for l in prog.splitlines():
            if 'interpreter:' in l:
                interp = l.split('interpreter:')[1].strip().rstrip(']')
                if resolve(interp) is None:
                    dangling.append((name, f'INTERP {interp}'))
        for lib in needs:
            if any(resolve(f'{d}/{lib}') for d in libdirs + extra):
                continue
            dangling.append((name, lib))

print(f'{len(entries)} files, {len(links)} symlinks, {elves} ELF objects')
if dangling:
    print('DANGLING dependencies:')
    for name, lib in dangling:
        print(f'  {name}: needs {lib}')
    sys.exit(1)
print('closure: every interpreter and DT_NEEDED resolves inside the archive')
PYEOF
echo 'check-initramfs-closure: PASS'
