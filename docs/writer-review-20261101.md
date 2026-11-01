# Offline writer review, 2026-11-01

Reviewed source: 0a95eef (published 0.2.0 writer lineage).

The CLI implements public-field configuration requests, server configuration,
server disabling, a managed firewall event and checksum-verified restore.
Developer-record hashes and native Mystic binary hashes gate writes. Private
fields and unknown layouts are rejected. Backups include SHA-256 and target
metadata, and data is compared again immediately before replacement.

## Remaining qualification and correctness work

- `msafeio.pas / CommitData`: Windows holds the root writer lock, but does not
  keep the target DAT exclusively open throughout the transaction. Another
  program can change the target after the final content check. The root lock
  coordinates mdatmod instances only. Native process checks cannot remove this
  race against unrelated writers. Qualify a target-handle strategy on Windows
  before claiming equivalent Linux/Windows locking guarantees.
- `RequireStopped`: Windows filters processes by their original executable
  names before checking paths. Renamed native executables are not detected.
  Linux additionally compares native inode identity, but arbitrary copied and
  renamed executables are not covered by the name checks. Offline operation
  must remain an operator precondition as well as an additional process guard.
- The write-binary allowlist covers Linux x86-64 A48/A49 and Windows x86/x64
  A49. ARM release archives do not imply qualified ARM Mystic writes. Add
  measured native fixtures and tests before extending this list.
- Release CI invokes read/refusal/self-tests, not `tests/test_writer.py` with
  native vendor fixtures. The Windows writer test also skips the busy-process
  and symlink cases exercised on Linux. Include these tests in qualification
  rather than treating a green archive build as a complete writer test.
- Linux replacement fsyncs Root, even when the target resides in Root/data.
  The actual target directory and backup directory need synchronization for
  stronger power-loss durability guarantees. Atomic replacement alone does
  not guarantee persistence after power loss.
- Windows SavePrivate dereferences Data[0] for zero-length payloads. Guard the
  empty write before enabling range checks or supporting empty record files.

No production DAT files were changed during this review. Online writes remain
outside scope. These findings do not justify weakening profile or process checks.
