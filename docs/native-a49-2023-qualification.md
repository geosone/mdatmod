# Native A49 2023 build qualification — 2026-11-11

Mystic 1.12 A49 was published as prealpha more than once. The archive that is
downloadable today contains the Linux/64 build compiled 2024/05/29, which the
writer already admits. Existing systems may still run the earlier build
compiled 2023/04/30. It ships the identical records.112
(`4575a20c3cb3c7ec3180e98ab2edbef7ae44da417f870c2e314e1874d1068363`), so the
record layout is the same; only the executable hash differs.

Admitted Linux x86-64 `mystic` hash:

- A49 2023/04/30: `c04c0b3f0ac9dd2e6df982084d3c847d5b663a27524746b5f2af02c9ad63e617`

The binary came from an operator's existing installation. It is not part of
this repository and is not redistributed.

## Checks

The test ran in an isolated Debian 12 systemd container without a network
(`--network none`), on a copy of that installation:

- `mdatmod profile` identifies `1.12 A49` from the docs hash.
- `set-record` rewrote the Shell, Name and Flags fields of two events and
  created a new interval event with a unique UID. The vendor MIS loaded all
  events ("Starting 7 event(s)").
- MIS executed the rewritten interval event with an absolute command and
  EventPrefix cleared, and reported each run result.
- A burst of connections made MIS auto-ban a loopback address. MIS ran the
  rewritten IP Blocked event, which passed the address to the firewall client.
- MIS stopped normally through its native shutdown and left no busy
  semaphore.

The generic layout check (`tests/test_schema.py`) passes for this
records.112 as for the 2024 build.
