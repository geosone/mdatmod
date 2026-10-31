"""Hash and refusal tests; optional real vendor fixture stays outside Git."""
import hashlib
import pathlib
import subprocess
import sys
import tempfile

exe = pathlib.Path(sys.argv[1]).resolve()
subprocess.run([str(exe), '--self-test'], check=True)
with tempfile.TemporaryDirectory(prefix='mdatmod-test-') as directory:
    root = pathlib.Path(directory)
    for count in [0, 1, 55, 56, 63, 64, 65, 127, 128, 257, 4096]:
        data = bytes((x * 17 + 3) % 256 for x in range(count))
        path = root / 'hash-input.bin'
        path.write_bytes(data)
        result = subprocess.run([str(exe), '--hash', str(path)], capture_output=True, text=True, check=True)
        assert result.stdout.strip() == hashlib.sha256(data).hexdigest(), count
    (root / 'docs').mkdir()
    (root / 'docs/records.112').write_text('unqualified profile')
    dat = root / 'mystic.dat'
    dat.write_bytes(b'private-canary-' * 512)
    original = dat.read_bytes()
    for arguments in [('inspect', str(root)), ('get', str(root), 'SysopPW'), ('set', str(root), 'BBSName', 'Changed')]:
        result = subprocess.run([str(exe), *arguments], capture_output=True, text=True)
        assert result.returncode != 0
        assert 'private-canary' not in result.stdout + result.stderr
        assert dat.read_bytes() == original
    assert not list(root.rglob('*.bak'))
if len(sys.argv) == 3:
    vendor = pathlib.Path(sys.argv[2]).resolve()
    before = hashlib.sha256((vendor / 'mystic.dat').read_bytes()).hexdigest()
    subprocess.run([str(exe), 'inspect', str(vendor)], check=True)
    result = subprocess.run([str(exe), 'get', str(vendor), 'SystemPW'], capture_output=True)
    assert result.returncode != 0
    assert hashlib.sha256((vendor / 'mystic.dat').read_bytes()).hexdigest() == before
print('PASS hash padding boundaries, unknown-profile refusal, private-field refusal and unchanged DAT bytes.')
