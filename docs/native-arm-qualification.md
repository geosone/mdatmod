# Native ARM write qualification — 2026-11-01

These tests ran on real ARM hardware, with native Docker userspaces. QEMU was
not used for this qualification. Separate Debian 12 (bookworm) and Debian 13
(trixie) images were used on the aarch64 and ARMHF test hosts.

| Mystic | Tool architecture | Debian 12 | Debian 13 |
|---|---|---|---|
| 1.12 A48 | arm64 | PASS | PASS |
| 1.12 A48 | armhf | PASS | PASS |
| 1.12 A49 | armhf | PASS | PASS |

A49 ARM64 was not present in the public prealpha index. Do not infer support
for an unavailable binary from the A48 ARM64 result.

## Vendor provenance

Archives were downloaded from the official Mystic download directories. No
vendor binary or records.112 is committed or redistributed here.

| Archive | SHA-256 |
|---|---|
| mys112a48_p32.zip | 29326461d4b66cfc45cd79c87403e20477ce04c95df1432f9d32cdc55633e55e |
| mys112a48_p64.zip | 9dcc6d508fc9e3e1731876ec6625c9858264dd1c533801992eb6316ae2f37046 |
| mys112a49_p32.zip | 6f7a4f9eb0c833f707ec4299736412046fb2d65514c949b9aafd908689c04790 |

Exact native Mystic binary hashes admitted by the writer:

- A48 armhf: `50e68574be0b044fc7a96f7aa57a196ec3450fe4eb4a0a163652f400b7f57bf3`
- A48 arm64: `db0cedcf3b293f9b8ab007bebe480f118da189a307f0a636b03a5a91201946d8`
- A49 armhf: `91077e44fa992bbac287d65e471389209a392bc863418886bcff02849e40d74a`

The A48 records hash is `7aec6ca491c5868d7c43d33298c910d092e8b2902df02ff634cef6bfe2cb99ef`;
A49 is `4575a20c3cb3c7ec3180e98ab2edbef7ae44da417f870c2e314e1874d1068363`.

## Checks and discovered ABI issue

`tools/writerlayoutprobe.pas` compiles the actual vendor records on the target
CPU. It verifies all written config/server/event field offsets and reserved
sizes, plus the A49 log roller fields. Record sizes are 8192/384/640 bytes.
A48 retains the vendor's A47 data marker; no marker is relabeled.

Native runs exposed incorrect FPC 3.2.2 BaseUnix constants on both ARM targets.
The Linux architecture headers (`bits/fcntl.h`) define O_DIRECTORY as octal
040000 and O_NOFOLLOW as octal 0100000. FPC returned the x86 constants instead.
`mlinuxflags.pas` supplies the ARM values. `tools/openflagprobe.pas` checks a
real directory open and an ELOOP refusal for a symlink, rather than checking
constant values alone. Existing x86 flag values are unchanged.

The ARM32 vendor executables are hard-float ELF files naming /lib/ld-linux.so.3.
The test image supplies that legacy name as an alias to ld-linux-armhf.so.3.
This change is limited to the disposable image and does not modify a host BBS.

Each matrix entry runs hash/refusal tests, config/server/event writes, byte
preservation, backup/checksum/restore, empty events, running and renamed process
refusal and symlink refusal. The native MUTIL then reads rewritten paths and
completes an empty synthetic AllFiles export with a normal shutdown. Tests copy
vendor fixtures and leave their source DAT bytes unchanged.

Logs: [qualification/arm-20261101](qualification/arm-20261101).
Runtime recipe: [Dockerfile.native-arm](../tests/Dockerfile.native-arm).
These results do not authorize online writes or arbitrary unqualified binaries.
