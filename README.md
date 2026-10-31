# datmod

Profile-validated Mystic DAT utility.

Status: repository and requirements prepared; no qualified executable release yet.

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
