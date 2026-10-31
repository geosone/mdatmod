# mdatmod

Profile-validated Mystic DAT utility.

Status: Pascal read-only research implementation with measured A45-A49 profiles.
No write-capable or production-qualified release yet.

## Distribution

Windows releases use ZIP archives; Linux releases use tar.gz archives. Extract
beside Mystic in `/opt/mystic` or `C:\Mystic`. No MSI, DEB, system service,
global PATH change or machine-wide installation is planned for this small tool.
Each archive contains exactly one native executable and README.txt. Embed
profiles/data in the program; do not ship script wrappers, helper DLLs or
sidecar configuration. Identify architecture and runtime/library requirements
in the README. Checksums are published beside the archive on GitHub.
There is no release artifact until native tests pass.

## Requirements

- Read fields only through identified Mystic record profiles.
- Validate file sizes, vendor record definitions and runtime/binary identity.
- Preserve reserved bytes and unrelated records; back up before every write.
- Refuse writes when process/lock state cannot be established.
- The exact MIS/Mystic running/stopped write policy still needs operator clarification.
- No raw arbitrary offset writer and no attempt to bypass Mystic locks.
- Tests use synthetic fixtures and isolated Mystic nodes only.

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
records are not exposed. Writes are deliberately unimplemented pending offline
process/lock policy, binary qualification and native write/rollback tests.
