# Linux i386 (L32) A48/A49 qualification

Date: 2026-11-20. mdatmod 0.6.2 admits the 32-bit Linux Mystic builds from the
official archives for writing. They exist for existing L32 installations on
amd64 Debian hosts; the mysticd installer updates them as L32 and never
installs L32 freshly.

| Version | Archive | `mystic` SHA-256 |
| --- | --- | --- |
| 1.12 A48 | https://mysticbbs.com/downloads/mys112a48_l32.rar | `2d02b37ea2910eda0ef9741061910c43e4eb0bede27353e50fb9a0f01d90aef3` |
| 1.12 A49 | https://mysticbbs.com/downloads/prealpha/mys112a49_l32.rar | `af9e06b175548d05952b4e664e5a383f6810db4764fe1e9a79c3c3cc25c79ac7` |

Both archives install a `docs/records.112` that is byte-identical to the
x86-64 one of the same version (A48 `7aec6ca4...99ef`, A49 `4575a20c...8363`),
so the record profiles are unchanged. A47 stays read-only, as on x86-64.

Native test: Debian 13 amd64 container with `libc6:i386` (the L32 programs are
dynamically linked against the i386 C library), vendor installers run with
`install auto` into isolated fixture roots. The mysticd installer's
`tests/test_native_mystic_update.ps1` passed for:

- A48 L32 to A49 L32, with a populated file base;
- A47 L32 to A49 L32 through the pinned A48 L32 packing stage, with an
  unavailable file, an injected interruption after A48 packing and rollback;
- adoption of an existing A48 L32 installation.

Each run covers the mdatmod configuration writes, the vendor upgrade, MPL
compilation, a real compiler failure with full-tree rollback and the
automatic installer run. No production data was used.
