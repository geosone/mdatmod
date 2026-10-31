"""Only copy vendor fixtures; never mutate the supplied installation."""
import hashlib
import os
from pathlib import Path
import pty
import shutil
import signal
import subprocess
import sys
import tempfile

exe = Path(sys.argv[1]).resolve()
source = Path(sys.argv[2]).resolve()
source_hash = hashlib.sha256((source / 'mystic.dat').read_bytes()).digest()
with tempfile.TemporaryDirectory(prefix='mdatmod-writer-') as directory:
    root = Path(directory) / 'bbs'
    root.mkdir()
    (root / 'docs').mkdir()
    shutil.copy2(source / 'docs/records.112', root / 'docs/records.112')
    for name in ['mystic', 'mis', 'mutil', 'mystic.dat']:
        shutil.copy2(source / name, root / name)
    (root / 'data').mkdir()
    for name in ['servers.dat', 'event.dat']:
        shutil.copy2(source / 'data' / name, root / 'data' / name)
    dat = root / 'mystic.dat'
    original = dat.read_bytes()

    def run(*args, ok=True):
        result = subprocess.run([str(exe), *map(str, args)], capture_output=True, text=True)
        assert (result.returncode == 0) == ok, result.stderr
        return dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)

    run('set', root, 'BBSName', 'Offline test')
    assert dat.read_bytes() == original
    changed = run('set', root, 'BBSName', 'Offline test', '--apply')
    after = dat.read_bytes()
    assert after[:989] == original[:989] and after[1020:] == original[1020:]
    backup = Path(changed['Backup'])
    assert backup.read_bytes() == original
    assert backup.with_suffix('.dat.sha256').is_file()
    if os.name != 'nt':
        assert backup.stat().st_mode & 0o077 == 0
    run('restore', root, backup, '--apply')
    assert dat.read_bytes() == original
    for field, value in [('SystemPW', 'private'), ('BBSName', 'x' * 31), ('BBSName', '\x1b[2J')]:
        run('set', root, field, value, '--apply', ok=False)
        assert dat.read_bytes() == original

    request = Path(directory) / 'fields.ini'
    request.write_text('[Fields]\nBBSName=Batch test\nDataPath=' + str(root / 'data') + '/\n')
    run('set-config', root, request, '--apply')
    server_before = (root / 'data/servers.dat').read_bytes()
    request.write_text('[Fields]\nActive=true\nIPv4Adapter=127.0.0.1\nPort=24554\nSSLPort=24553\n')
    server_change = run('set-server', root, 'BINKP', request, '--apply')
    server_after = (root / 'data/servers.dat').read_bytes()
    assert len(server_after) == len(server_before)
    bink_offset = next(offset for offset in range(0, len(server_before), 384)
                       if server_before[offset + 67:offset + 72] == b'BINKP')
    assert server_after[:bink_offset] == server_before[:bink_offset]
    assert server_after[bink_offset + 384:] == server_before[bink_offset + 384:]
    run('restore', root, server_change['Backup'], '--apply')
    assert (root / 'data/servers.dat').read_bytes() == server_before
    request.write_text('[Fields]\nActive=false\nShell=/usr/bin/pwsh -NoProfile -File /opt/mystic/banunban.ps1 @IP@\n')
    event_before = (root / 'data/event.dat').read_bytes()
    event_change = run('ban-event', root, request, '--apply')
    assert (root / 'data/event.dat').stat().st_size % 640 == 0
    run('restore', root, event_change['Backup'], '--apply')
    assert (root / 'data/event.dat').read_bytes() == event_before

    if os.name != 'nt':
        master, slave = pty.openpty()
        process = subprocess.Popen([str(root / 'mystic'), '-cfg'], cwd=root,
                                   stdin=slave, stdout=slave, stderr=slave)
        os.close(slave)
        try:
            os.kill(process.pid, signal.SIGSTOP)
            before_busy = dat.read_bytes()
            run('set', root, 'BBSName', 'Must refuse', '--apply', ok=False)
            assert dat.read_bytes() == before_busy
        finally:
            process.kill()
            process.wait()
            os.close(master)
        # A symlink cannot redirect the write target outside its qualified root.
        dat.rename(root / 'original.dat')
        dat.symlink_to(root / 'original.dat')
        run('set', root, 'BBSName', 'Must refuse', '--apply', ok=False)
    assert hashlib.sha256((source / 'mystic.dat').read_bytes()).digest() == source_hash
print('PASS offline config/server/event writes, byte preservation, backup/checksum, restore, private/invalid-field refusal, busy process and symlink guards')
