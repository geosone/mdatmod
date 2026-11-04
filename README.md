# mdatmod

Profile-validated Mystic DAT utility.

Status: Pascal implementation with measured A45-A49 profiles. Offline writes are
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
during qualification; that combination is not claimed. No release archive implies support for other binaries.

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
