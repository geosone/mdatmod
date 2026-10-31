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
arm64 and armhf through buildx/QEMU in Debian bullseye, Windows x86/x64 with a
pinned Lazarus/FPC, including the PE machine check and the hash/refusal test.
Tagging `v*` publishes the archives and `SHA256SUMS`. The writer test needs the
non-redistributable vendor `records.112` and an isolated Mystic installation, so
it stays a qualified-machine step before a tag.

## Requirements

- Read fields only through identified Mystic record profiles.
- Validate file sizes, vendor record definitions and runtime/binary identity.
- Preserve reserved bytes and unrelated records; back up before every write.
- Refuse writes when process/lock state cannot be established.
- The exact MIS/Mystic running/stopped write policy still needs operator clarification.
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
A49 MIS log roller fields. `set-server` edits one protocol record in
servers.dat; `ban-event` creates or updates the managed IP Blocked event.
Requests are a small INI with one `[Fields]` section. Values are printable
ASCII; no code page is guessed.

`python3 tests/test_writer.py build/mdatmod VENDOR_ROOT` copies an isolated
vendor installation, then checks plans, writes, byte preservation, backups,
restore, refusal of private/overlong fields, a stopped process and a symlinked
DAT.
