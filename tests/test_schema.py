"""Compare mdatmod's records.112 layouts with Free Pascal's own.

Usage: test_schema.py MDATMOD RECORDS.112 [RECORDS.112 ...]

For each vendor records.112 the test builds a synthetic root (docs/records.112
plus a zero-filled mystic.dat carrying the data-version marker and an absolute
DataPath), asks "mdatmod schema" for every supported DAT file, then compiles a
probe with fpc that includes the same records.112 and prints the real offset
and size of every field. Set fields are also written with their lowest and
highest member to check the bit layout. Every value must match.

Needs fpc on PATH. Only temporary files are written.
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

FILES = ['mystic.dat', 'archive.dat', 'event.dat', 'security.dat', 'mbases.dat',
         'fbases.dat', 'groups_g.dat', 'protocol.dat', 'servers.dat',
         'echonode.dat', 'echogroup.dat', 'qwknet.dat', 'history.dat']

# RecConfig offset 98 is DataPath, String[80], in every supported profile.
DATA_PATH_OFFSET = 98

PROBE_HEADER = """program SchemaProbe;
{$mode objfpc}{$H+}
uses SysUtils;
const OSBIT = '/probe';
{$I records.112}
"""


def compile_and_run(directory, source):
    probe = directory / 'probe.pas'
    probe.write_text(source)
    build = subprocess.run(['fpc', '-O-', '-FE' + str(directory), str(probe)],
                           cwd=directory, capture_output=True, text=True)
    assert build.returncode == 0, build.stdout[-3000:]
    result = subprocess.run([str(directory / 'probe')], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    return result.stdout.splitlines()


def schema(mdatmod, root, name):
    result = subprocess.run([str(mdatmod), 'schema', str(root), name],
                            capture_output=True, text=True)
    if result.returncode != 0:
        return None, result.stderr.strip()
    values = dict(line.split('=', 1) for line in result.stdout.splitlines())
    fields = {key[6:]: value.split(',') for key, value in values.items()
              if key.startswith('Field.')}
    return (values['Type'], int(values['RecordBytes']), fields), None


def check(mdatmod, records):
    text = records.read_text(encoding='latin-1')
    version = re.search(r"mysDataChanged\s*=\s*'([^']+)'", text).group(1)
    with tempfile.TemporaryDirectory(prefix='mdatmod-schema-') as name:
        directory = Path(name)
        (directory / 'docs').mkdir()
        (directory / 'data').mkdir()
        (directory / 'records.112').write_bytes(records.read_bytes())
        (directory / 'docs' / 'records.112').write_bytes(records.read_bytes())

        size = int(compile_and_run(directory, PROBE_HEADER +
                                   'begin Writeln(SizeOf(RecConfig)); end.\n')[0])
        config = bytearray(size)
        marker = version.encode('ascii')
        config[0] = len(marker)
        config[1:1 + len(marker)] = marker
        data_path = (str(directory / 'data') + '/').encode('ascii')
        assert len(data_path) <= 80, 'temporary path too long for DataPath'
        config[DATA_PATH_OFFSET] = len(data_path)
        config[DATA_PATH_OFFSET + 1:DATA_PATH_OFFSET + 1 + len(data_path)] = data_path
        (directory / 'mystic.dat').write_bytes(bytes(config))

        layouts = {}
        lines = ['var']
        body = ['begin']  # replaced by procedures below
        for index, name in enumerate(FILES):
            layout, error = schema(mdatmod, directory, name)
            if layout is None and ('Unknown developer records' in error or 'not qualified' in error):
                print('SKIP %s: %s' % (records, error))
                return
            if layout is None:
                # Older records may lack a type; a missing type must be refused.
                assert 'no storable' in error or 'Unknown' in error, (name, error)
                continue
            layouts[name] = layout
            type_name, record_bytes, fields = layout
            variable = 'V%d' % index
            lines.append('    %s: %s;' % (variable, type_name))
            body.append("    Writeln('%s|=|', SizeOf(%s));" % (name, variable))
            for field, (offset, width, kind, *rest) in fields.items():
                body.append("    Writeln('%s|%s|', PtrUInt(@%s.%s) - PtrUInt(@%s), ',', SizeOf(%s.%s));"
                            % (name, field, variable, field, variable, variable, field))
                if kind == 'set':
                    low, high = rest[0].split('-')
                    body.append('    FillChar(%s.%s, SizeOf(%s.%s), 0);' % (variable, field, variable, field))
                    body.append('    %s.%s := [%s, %s];' % (variable, field, low, high))
                    body.append("    Write('%s|%s#bits|');" % (name, field))
                    body.append('    for I := 0 to SizeOf(%s.%s) - 1 do Write(IntToHex(PByte(@%s.%s)[I], 2));'
                                % (variable, field, variable, field))
                    body.append('    Writeln;')
        lines.append('    I: Integer;')
        # One huge main block exceeds FPC's register allocator; split the
        # statements into procedures that never cut a set check in half.
        statements = body[1:]
        procedures = []
        chunk = []
        for statement in statements:
            chunk.append(statement)
            if len(chunk) >= 150 and statement == '    Writeln;' or \
                    len(chunk) >= 150 and 'Write(' not in statement and 'FillChar' not in statement \
                    and ':= [' not in statement and 'for I' not in statement:
                procedures.append(chunk)
                chunk = []
        if chunk:
            procedures.append(chunk)
        body = []
        for number, chunk in enumerate(procedures):
            body.append('procedure Part%d;' % number)
            body.append('begin')
            body.extend(chunk)
            body.append('end;')
        body.append('begin')
        body.extend('    Part%d;' % number for number in range(len(procedures)))
        body.append('end.')
        assert layouts, records
        output = compile_and_run(directory, PROBE_HEADER + '\n'.join(lines + body) + '\n')

        actual = {}
        for line in output:
            name, field, value = line.split('|', 2)
            actual[(name, field)] = value
        checked = 0
        for name, (type_name, record_bytes, fields) in layouts.items():
            assert int(actual[(name, '=')]) == record_bytes, (records, name)
            for field, (offset, width, kind, *rest) in fields.items():
                assert actual[(name, field)] == '%s,%s' % (offset, width), \
                    (records.parent.name, name, field, actual[(name, field)], offset, width)
                if kind == 'set':
                    low, high = (int(value) for value in rest[0].split('-'))
                    expected = bytearray(int(width))
                    for member in (low, high):
                        expected[member // 8] |= 1 << (member % 8)
                    assert actual[(name, field + '#bits')] == expected.hex().upper(), (name, field)
                checked += 1
        print('PASS %s (%s): %d files, %d fields' % (records, version, len(layouts), checked))


mdatmod_path = Path(sys.argv[1]).resolve()
for argument in sys.argv[2:]:
    check(mdatmod_path, Path(argument).resolve())
