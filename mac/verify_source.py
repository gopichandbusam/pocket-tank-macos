#!/usr/bin/env python3
"""Check upstream core parity and local source/resource provenance of a built Mac app."""
from pathlib import Path
import hashlib
import json
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASELINE = 'c57960535d85a3432387b34e4a2c456a7f06be64'
APP = ROOT / 'dist/Pocket Tank.app'

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)

def digest(data):
    return hashlib.sha256(data).hexdigest()

def code_sections(data):
    """Read per-architecture code from thin or universal 64-bit Mach-O images."""
    if data[:4] in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        wide = data[:4] == b'\xca\xfe\xba\xbf'
        count = struct.unpack_from('>I', data, 4)[0]
        result = {}
        for n in range(count):
            position = 8 + n * (32 if wide else 20)
            offset, length = struct.unpack_from('>QQ' if wide else '>II', data, position + 8)
            result.update(code_sections(data[offset:offset+length]))
        return result
    if struct.unpack_from('<I', data)[0] != 0xfeedfacf:
        raise RuntimeError('Expected a 64-bit Mach-O image')
    commands = struct.unpack_from('<I', data, 16)[0]
    offset = 32
    for _ in range(commands):
        command, size = struct.unpack_from('<II', data, offset)
        if command == 0x19:
            count = struct.unpack_from('<I', data, offset + 64)[0]
            for n in range(count):
                section = offset + 72 + n * 80
                name = data[section:section+16].rstrip(b'\0')
                segment = data[section+16:section+32].rstrip(b'\0')
                if name == b'__text' and segment == b'__TEXT':
                    length = struct.unpack_from('<Q', data, section + 40)[0]
                    file_offset = struct.unpack_from('<I', data, section + 48)[0]
                    architecture = struct.unpack_from('<II', data, 4)
                    return {architecture: data[file_offset:file_offset+length]}
        offset += size
    raise RuntimeError('No executable code section')

if __name__ == '__main__':
    paths = git('ls-tree', '-r', '--name-only', BASELINE, '--', 'common', 'model', 'assets', 'firmware').decode().splitlines()
    for relative in paths:
        original = git('show', BASELINE + ':' + relative)
        assert (ROOT / relative).read_bytes() == original, 'Upstream core changed: ' + relative
    print(f'PASS: {len(paths)} tracked core/model/assets/firmware files match upstream {BASELINE}')
    provenance = json.loads((APP / 'Contents/Resources/Build Provenance.json').read_text())
    assert provenance['upstream_commit'] == BASELINE
    for relative, expected in provenance['source_sha256'].items():
        assert digest((ROOT / relative).read_bytes()) == expected, 'Source mismatch: ' + relative
    for relative, expected in provenance['resource_sha256'].items():
        local = (ROOT / relative).read_bytes()
        bundled = (APP / 'Contents/Resources' / relative).read_bytes()
        assert digest(local) == digest(bundled) == expected, 'Resource mismatch: ' + relative
    assert code_sections((ROOT / 'sim/fishsim').read_bytes()) == code_sections((APP / 'Contents/MacOS/PocketTank').read_bytes()), 'Compiled machine code differs'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(APP)], check=True)
    print('PASS: signed bundle matches recorded local source/resources and simulator machine code')
