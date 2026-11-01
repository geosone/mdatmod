"""Read a DAT configuration written by mdatmod with the real native MUTIL."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

exe = Path(sys.argv[1]).resolve()
source = Path(sys.argv[2]).resolve()
suffix = '.exe' if os.name == 'nt' else ''
original = hashlib.sha256((source / 'mystic.dat').read_bytes()).digest()
with tempfile.TemporaryDirectory(prefix='mdatmod-native-',
                                 dir=Path(tempfile.gettempdir()).anchor if os.name == 'nt' else None) as directory:
    root = Path(directory) / 'bbs'
    root.mkdir()
    (root / 'docs').mkdir()
    for name in ['data', 'logs', 'msgs', 'themes', 'semaphore', 'attach']:
        (root / name).mkdir()
    for name in ['mystic.dat', f'mystic{suffix}', f'mutil{suffix}']:
        shutil.copy2(source / name, root / name)
    shutil.copy2(source / 'docs/records.112', root / 'docs/records.112')
    shutil.copy2(source / 'data/servers.dat', root / 'data/servers.dat')
    # Use an empty synthetic file-base set so MUTIL cannot follow vendor paths.
    (root / 'data/fbases.dat').write_bytes(b'')
    fields = ['[Fields]', 'BBSName=Native roundtrip']
    for field, folder in [('SystemPath', ''), ('DataPath', 'data'),
                          ('LogsPath', 'logs'), ('MsgsPath', 'msgs'),
                          ('ThemePath', 'themes'), ('SemaPath', 'semaphore'),
                          ('AttachPath', 'attach')]:
        fields.append(f'{field}={root / folder}{os.sep}')
    request = Path(directory) / 'request.ini'
    request.write_text('\n'.join(fields) + '\n')
    subprocess.run([str(exe), 'set-config', str(root), str(request), '--apply'],
                   capture_output=True, check=True)
    subprocess.run([str(exe), 'disable-servers', str(root), '--apply'],
                   capture_output=True, check=True)
    log = root / 'logs/native.log'
    export = root / 'allfiles.txt'
    ini = root / 'native.ini'
    ini.write_text('[General]\nGenerateAllFiles=true\nloglevel=2\nlogcache=false\n'
                   f'logfile={log}\nmystic_directory={root / "mystic.dat"}\n'
                   f'[GenerateAllFiles]\nfilename={export}\n')
    before = ini.read_bytes()
    result = subprocess.run([str(root / f'mutil{suffix}'), ini.name, '-NOSCREEN'],
                            cwd=root, capture_output=True, timeout=30)
    assert result.returncode == 0, result.returncode
    assert log.is_file() and export.is_file(), 'Native export did not run'
    content = log.read_text(errors='replace')
    assert 'Generating AllFiles List' in content
    assert 'Added 0 file(s)' in content
    assert 'Shutdown Normal (0)' in content
    assert ini.read_bytes() == before
assert hashlib.sha256((source / 'mystic.dat').read_bytes()).digest() == original
print('PASS native MUTIL reads the rewritten paths and completes its export')
