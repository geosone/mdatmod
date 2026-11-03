"""Only copy vendor fixtures; never mutate the supplied installation."""
import hashlib
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile

exe = Path(sys.argv[1]).resolve()
source = Path(sys.argv[2]).resolve()
# Native binaries keep their platform suffix; the DAT names do not.
suffix = '.exe' if os.name == 'nt' else ''
source_hash = hashlib.sha256((source / 'mystic.dat').read_bytes()).digest()
with tempfile.TemporaryDirectory(prefix='mdatmod-writer-',
                                 dir=Path(tempfile.gettempdir()).anchor if os.name == 'nt' else None) as directory:
    root = Path(directory) / 'bbs'
    root.mkdir()
    (root / 'docs').mkdir()
    shutil.copy2(source / 'docs/records.112', root / 'docs/records.112')
    for name in [f'mystic{suffix}', f'mis{suffix}', f'mutil{suffix}', 'mystic.dat']:
        shutil.copy2(source / name, root / name)
    (root / 'data').mkdir()
    for name in ['servers.dat', 'event.dat']:
        shutil.copy2(source / 'data' / name, root / 'data' / name)
    installed_tool = root / exe.name
    shutil.copy2(exe, installed_tool)
    exe = installed_tool
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
    for field, value in [('SystemPW', 'private'), ('BBSName', 'x' * 31)]:
        run('set', root, field, value, '--apply', ok=False)
        assert dat.read_bytes() == original
    # Windows drops control characters from command-line arguments, so a
    # command-line value would silently become a different valid string.
    # The installer passes values through a request file; check that path.
    if os.name == 'nt':
        control = Path(directory) / 'control.ini'
        control.write_bytes(b'[Fields]\nBBSName=before\x1bafter\n')
        run('set-config', root, control, '--apply', ok=False)
        assert dat.read_bytes() == original
    else:
        run('set', root, 'BBSName', '\x1b[2J', '--apply', ok=False)
        assert dat.read_bytes() == original

    request = Path(directory) / 'fields.ini'
    request.write_text('[Fields]\nBBSName=Batch test\nDataPath=' + str(root / 'data') + '/\n')
    run('set-config', root, request, '--apply')
    if run('inspect', root)['Profile'] == '1.12 A49':
        # DateFmt is String[25]: one length byte and 25 reserved payload bytes.
        # These offsets are measured against the hashed vendor records by the
        # layout probe; no roller flags, retention or cached-writing bits move.
        log_fields = {'MISLogDateFormat': 4582, 'NodeLogDateFormat': 4617,
                      'PollLogDateFormat': 4652, 'QWKLogDateFormat': 4687}
        before_logs = dat.read_bytes()
        stamp = 'YYYYMMDD HH:II:SS'
        request.write_text('[Fields]\n' + ''.join(k + '=' + stamp + '\n' for k in log_fields))
        run('set-config', root, request)
        assert dat.read_bytes() == before_logs
        log_change = run('set-config', root, request, '--apply')
        expected = bytearray(before_logs)
        for field, offset in log_fields.items():
            expected[offset:offset + 26] = bytes([len(stamp)]) + stamp.encode() + bytes(25 - len(stamp))
            result = subprocess.run([str(exe), 'get', str(root), field], capture_output=True, text=True)
            assert result.returncode == 0 and result.stdout.strip() == stamp, result.stderr
        assert dat.read_bytes() == bytes(expected)
        run('restore', root, log_change['Backup'], '--apply')
        assert dat.read_bytes() == before_logs
        request.write_text('[Fields]\nNodeLogDateFormat=' + 'x' * 26 + '\n')
        run('set-config', root, request, '--apply', ok=False)
        assert dat.read_bytes() == before_logs
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

    # Empty event files exercise zero-length private backups and restoration.
    events = root / 'data/event.dat'
    events.write_bytes(b'')
    empty_change = run('ban-event', root, request, '--apply')
    assert Path(empty_change['Backup']).read_bytes() == b''
    run('restore', root, empty_change['Backup'], '--apply')
    assert events.read_bytes() == b''
    events.write_bytes(event_before)

    if os.name != 'nt':
        import pty
        renamed = root / 'renamed-native'
        shutil.copy2(root / 'mystic', renamed)
        for native in (root / 'mystic', renamed):
            master, slave = pty.openpty()
            process = subprocess.Popen([str(native), '-cfg'], cwd=root,
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
    if os.name == 'nt':
        import ctypes
        from ctypes import wintypes
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.CreateFileW.restype = wintypes.HANDLE
        kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD,
                                      wintypes.DWORD, ctypes.c_void_p,
                                      wintypes.DWORD, wintypes.DWORD,
                                      wintypes.HANDLE]
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        # A foreign reader that disallows replacement must prevent a write.
        handle = kernel.CreateFileW(str(dat), 0x80000000, 1, None, 3, 0, None)
        assert handle != wintypes.HANDLE(-1).value
        try:
            before_locked = dat.read_bytes()
            run('set', root, 'BBSName', 'Locked refusal', '--apply', ok=False)
            assert dat.read_bytes() == before_locked
        finally:
            kernel.CloseHandle(handle)
        # CREATE_SUSPENDED gives a deterministic running native process without
        # executing a login/configuration path or depending on a console window.
        renamed = root / 'renamed-native.exe'
        shutil.copy2(root / 'mystic.exe', renamed)
        for native in (root / 'mystic.exe', renamed):
            process = subprocess.Popen([str(native), '-cfg'], cwd=root,
                                       creationflags=0x00000004)
            try:
                before_busy = dat.read_bytes()
                run('set', root, 'BBSName', 'Busy refusal', '--apply', ok=False)
                assert dat.read_bytes() == before_busy
            finally:
                process.kill()
                process.wait()
    assert hashlib.sha256((source / 'mystic.dat').read_bytes()).digest() == source_hash
guards = 'busy process and symlink guards' if os.name != 'nt' else 'Windows file-lock and native/renamed-process guards'
print('PASS offline config/server/event writes, byte preservation, backup/checksum, '
      f'restore, private/invalid-field refusal, {guards}')
