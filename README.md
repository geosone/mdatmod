# mdatmod

Profile-validated Mystic DAT utility.

Status: Pascal implementation with measured A45-A49 profiles and generic
records.112-based access to every non-personal DAT file. Offline writes are
implemented and pass the native writer tests on Linux and Windows.

## Distribution

Windows releases use ZIP archives; Linux releases use tar.gz archives. Extract
beside Mystic in `/opt/mystic` or `C:\Mystic`. No MSI, DEB, system service,
global PATH change or machine-wide installation is planned for this small tool.
Each archive contains exactly one native executable and README.txt, taken from
`packaging/README.txt`. Embed profiles/data in the program; do not ship script
wrappers, helper DLLs or sidecar configuration. Checksums are published beside
the archive on GitHub.

`.github/workflows/build.yml` builds and exercises every archive: Linux amd64,
arm64 and armhf through buildx/QEMU in Debian bookworm, Windows x86/x64 with a
pinned Lazarus/FPC, including the PE machine check and the hash/refusal test.
Tagging `v*` publishes the archives and `SHA256SUMS`. The writer test needs the
non-redistributable vendor `records.112` and an isolated Mystic installation, so
CI downloads pinned vendor installers for isolated amd64 and Windows x86/x64
writer tests; vendor data is never included in release archives.

## Requirements

- Read fields only through identified Mystic record profiles.
- Validate file sizes, vendor record definitions and runtime/binary identity.
- Preserve reserved bytes and unrelated records; back up before every write.
- Refuse writes when process/lock state cannot be established.
- Writes are explicitly permitted only while the native BBS processes are stopped.
- No raw arbitrary offset writer and no attempt to bypass Mystic locks.
- Tests use synthetic fixtures and isolated Mystic nodes only.

Writes are offline only: MIS, Mystic, MUTIL, MIDE and UPGRADE must not run from
the target root. The program takes an exclusive lock on the root and on the DAT,
writes a private backup with SHA-256 and target reference, replaces the file
atomically and verifies the result. `restore` accepts only those backups.
Online writes for the future daemon are explicitly out of scope.

## Repository boundary

The program, its builds and tests live here. Installation/configuration integration
belongs to the separate mysticd repository. BBS artwork and presentation assets
belong to mystic-theme. Existing live data must not be changed without explicit
operator approval. License: GPL-3.0-only.

## Current source build

`make test` builds the single executable and runs hash self-tests.
`python3 tests/test_readonly.py build/mdatmod` checks hash padding boundaries,
refusal of unknown profiles/private fields and unchanged DAT bytes. An optional
third argument selects an existing isolated vendor fixture.

`mdatmod inspect ROOT` verifies the matching records.112 SHA-256, DAT size and
data-version marker. `mdatmod get ROOT FIELD` reads only an explicit public
configuration field allowlist; control bytes are escaped. Credentials and user
records are not exposed.

Write commands plan by default and change files only with `--apply`:

```text
mdatmod set ROOT FIELD VALUE [--apply]
mdatmod set-config ROOT REQUEST.ini [--apply]
mdatmod set-server ROOT PROTOCOL REQUEST.ini [--apply]
mdatmod disable-servers ROOT [--apply]
mdatmod ban-event ROOT REQUEST.ini [--apply]
mdatmod get-archive ROOT EXT OSTYPE
mdatmod set-archive ROOT EXT OSTYPE REQUEST.ini [--apply]
mdatmod restore ROOT BACKUP [--apply]
mdatmod check-offline ROOT
```

`set` covers the public mystic.dat string fields; `set-config` also covers the
A49 MIS log roller fields and all four A49 log timestamp formats.
`get` reads `MISLogDateFormat`, `NodeLogDateFormat`, `PollLogDateFormat` and
`QWKLogDateFormat`; batch `set-config` writes these qualified String[25] fields
without changing retention, rolling mode or caching. The filename date and
the per-entry timestamp are separate: DateFmt formats log entries. `set-server` edits one protocol record in
servers.dat; `ban-event` creates or updates the managed IP Blocked event.
Requests are a small INI with one `[Fields]` section. Values are printable
ASCII; no code page is guessed.

`python3 tests/test_writer.py build/mdatmod VENDOR_ROOT` copies an isolated
vendor installation, then checks plans, writes, byte preservation, backups,
restore, refusal of private/overlong fields, a stopped process and a symlinked
DAT.

## Native write qualification

Native writes are qualified for Linux x86-64 A48/A49, ARM64 A48, ARMHF
A48/A49 and Windows x86/x64 A49. The ARM matrix passed on real ARM hardware
with Debian 12 and 13 userspaces. No public A49 ARM64 binary was available
during qualification; that combination is not claimed. Linux x86-64 A49 admits
both the current 2024/05/29 download and the earlier 2023/04/30 prealpha build
([qualification](docs/native-a49-2023-qualification.md)). No release archive
implies support for other binaries.

The root writer lock coordinates mdatmod instances. Windows holds a read handle
that denies foreign writes while allowing atomic replacement. Linux holds flock
on the target inode. These checks supplement the operator requirement to stop
MIS, Mystic and utilities; they do not interlock with future starts or protect
against a privileged actor swapping filesystem paths. Stop automatic service
restarts during maintenance. Renamed executables inside the root are rejected.

Native qualification also tests foreign file locks, renamed processes, installed
mdatmod execution and empty event backups/restores. Unknown or inaccessible
candidate BBS processes fail closed. System processes without user-mode image
paths are skipped when they cannot correspond to a native file in the root.

ARM syscall compatibility: FPC 3.2.2 supplies x86 directory/no-follow open
flags on ARM. mdatmod uses the measured ARM/AArch64 ABI constants and tests
their actual kernel behavior. Vendor ARM32 executables require the legacy
/lib/ld-linux.so.3 loader name; the qualification image provides an alias to
the hard-float loader inside disposable containers only. See the source
qualification report for exact vendor hashes and the six native test runs.

A49 archive retention is exposed through `get` / `set-config` fields
MISLogFiles, NodeLogFiles, PollLogFiles and QWKLogFiles. Each is the vendor's
little-endian two-byte RecLogRoller.Files Word, accepting 0..65535. Zero disables
Mystic's own archive-count limit; external maintenance can then own expiry.
Other profiles remain rejected for these fields. Tests qualify preview,
whole-record byte preservation, numeric range rejection, readback and restore.

Command-line help is available with `--help`, `-h`, `/h` or `/?`, or by
running mdatmod without arguments. Help returns exit code zero and does not
require a Mystic installation. `/H` is accepted as well.

### A49 console and login codepages

`set-config` accepts symbolic `LocalCodePage=CP437|UTF8`,
`StartCodePage=CP437|UTF8` and `AskCodePage=Detect|Ask|CP437|UTF8`.
`get ROOT FIELD` returns the symbolic name. Numeric codepage identifiers are
rejected: Mystic's stored enums are not Windows codepage numbers.

These three fields are qualified for A49 only. Compiling the original, hashed
`records.112` establishes zero-based RecConfig byte offsets 1247, 1450 and 2007;
each is a Byte with a one-byte total reservation. The original A49 Linux
`mystic -cfg` was used in an isolated, path-remapped fixture to select every
Ask CodePage option and save/reopen the record: Detect=0, Ask=1, CP437=2, UTF8=3.
Local and Start codepage selectors use CP437=0, UTF8=1. The layout probe checks
the offsets; writer tests require exact single-byte changes and reject unsupported
values without touching the DAT. Existing binary, stopped-process, backup and
profile guards remain in force. Older profiles are not assigned A49 offsets.

Mystic's [Login/Matrix documentation](https://wiki.mysticbbs.com/doku.php?id=config_login_matrix)
distinguishes local Unix output from remote negotiation and CP437 storage. A
terminal using UTF-8 does not justify converting Mystic's stored DAT/ANSI data.

### Generic records from records.112

From 0.6.0 every Mystic DAT file below can be read, changed and extended by
field name. The layout is not embedded: mdatmod parses the installation's own
`docs/records.112` (the vendor developer records, already identified by
SHA-256 against a known profile) and computes each field's zero-based offset
and size with Free Pascal's packed-record rules (`{$PACKRECORDS 1}`; Byte,
Boolean and Char 1 byte; Word/SmallInt 2; LongInt/Cardinal 4; Int64/UInt64 8,
all little endian; `String[N]` one length byte plus N payload bytes; a set of
members below 32 takes 4 bytes, otherwise 32).

```text
mdatmod schema ROOT FILE                      field names, offsets, sizes, kinds
mdatmod list ROOT FILE [FIELD ...]            values of every record
mdatmod set-record ROOT FILE REQUEST.ini [--apply]
```

| File | Record type | Location |
| --- | --- | --- |
| mystic.dat | RecConfig (one record) | root |
| archive.dat | RecArchive | DataPath |
| event.dat | RecEvent | DataPath |
| security.dat | RecSecurity | DataPath |
| mbases.dat | RecMessageBase | DataPath |
| fbases.dat | RecFileBase | DataPath |
| groups_g.dat, groups_f.dat | RecGroup | DataPath |
| protocol.dat | RecProtocol | DataPath |
| servers.dat | ServerInfoRecord | DataPath |
| echonode.dat | RecEchoMailNode | DataPath |
| echogroup.dat | RecEchoMailGroup | DataPath |
| qwknet.dat | RecQwkNetwork | DataPath |
| history.dat | RecHistory | DataPath |

`users.dat` and `callers.dat` hold personal data and are refused. Credential
fields (`Password`, `CryptKey` and every field ending in `Pass` or `PW`, such
as `SysopPW` or `BinkPass`) are never printed; `schema` marks them `secret`.
They can still be written through a request file. Field names are those of
records.112 with element indexes and dots: `ExecDays[0]`,
`NetAddress[1].Zone`. `list` omits reserved padding (`Res`, `Reserved`,
`UNUSED`) unless it is named.

Values: numbers in decimal, booleans `true`/`false`, sets as a comma list of
members (`1,5,26`), strings and chars as printable ASCII. Any other byte is
written and printed as `\xNN`; a backslash is literal unless `x` and two hex
digits follow. No code page is guessed.

A request has three sections:

```ini
[Match]
Name=Daily Tasks
Shell=cron -f dbp.ini
[Fields]
Shell=/usr/bin/pwsh -NoProfile -File /opt/mystic/cron.ps1 -Apply
[Options]
Create=false
UniqueField=UID
```

`[Match]` must select exactly one record (`mystic.dat` takes only
`[Fields]`). With `Create=true` and no match, a zeroed record is appended,
takes the Match values and then the Fields; `UniqueField` gives it the
highest existing value plus one, as RecEvent's UID needs. Strings are
compared by their payload, a written string is zero-filled to its full
reservation, and every other byte of the file stays as it was. Records are
never deleted or reordered, because other files refer to record positions.
All write guards below apply unchanged; `restore` also returns an appended
record to the earlier file.

`tests/test_schema.py MDATMOD RECORDS.112 ...` builds a synthetic root per
records.112, takes every field from `schema` and compiles a Free Pascal probe
that includes the same records.112, then compares each offset, size and set
bit layout. It passed for the A44/A45, A46, A47, A48 and A49 records (1896 to
3947 fields over 13 files each); CI repeats it for A49. `test_writer.py`
covers plans, a field change, a created record with a unique UID, refusal of
ambiguous matches, credentials and personal files, and exact restore.

### A49 archive records

From 0.5.0, `get-archive ROOT EXT OSTYPE` and
`set-archive ROOT EXT OSTYPE REQUEST.ini [--apply]` read and write one
`data/archive.dat` record, found through the absolute DataPath. OSTYPE is
`Windows`, `Linux`, `macOS` or `All` (vendor values 0-3; OS/2 is not offered).
The extension has one to four letters or digits and is stored upper case.
Exactly one record may match the pair; duplicates are refused.

RecArchive is a packed 281-byte record. `tools/writerlayoutprobe.pas` checks
every zero-based offset and total reservation against the hashed A49
`records.112`: OSType Byte at 0, Active Boolean at 1, Desc String[30] at 2
(31 bytes), Ext String[4] at 33 (5 bytes), Pack, Unpack and View String[80] at
38, 119 and 200 (81 bytes each). Request fields are `Active`, `Description`,
`Pack`, `Unpack` and `View`. A missing pair is appended as a new record and
then needs `Active` and `Description`; existing record numbers stay unchanged.
Vendor records keep stale bytes after a string's length; a written field is
zero-filled to its full reservation, other fields keep their bytes. `restore`
also returns an appended record to the earlier file. Only the A49 profile is
accepted.

Mystic runs these commands through `/bin/sh -c` on Linux and `cmd` on
Windows, from the Mystic root, with `%1` the archive, `%2` the requested
member pattern and `%3` the temporary directory with a trailing separator.
Writer tests cover plans, exact byte changes, appending, restore and refusal
of overlong values, unknown fields, invalid extensions/OSTYPEs, control bytes
and an incomplete file. Native A49 MUTIL MassUpload with FILE_ID.DIZ import
read records written by this mdatmod on Linux x86-64 and Windows x86/x64;
the record commands themselves are qualified by the mysticd installer that
writes them.
