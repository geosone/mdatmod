# Mystic record layout comparison

Official archives were downloaded into an isolated development directory on
2026-10-31. The vendor installer was invoked only as
`install extract records* DESTINATION` in a private network namespace. No
full installation, BBS service, user login or live DAT change was performed.
Command reference: https://wiki.mysticbbs.com/doku.php?id=installation
Archive index: https://www.mysticbbs.com/downloads/

The complete vendor records.112 was compiled locally through a small Free Pascal
3.2.2 probe using PACKRECORDS 1. Its missing standalone OSBIT build constant was
supplied as `/64`; vendor record declarations were not edited. These are
measured record sizes, not proof that every field offset is compatible.

| Archive | docs version | DataChanged | RecConfig | RecUser | RecEvent | RecFileBase | RecFileList | RecMessageBase | RecEchoMailNode |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| A45 Linux x64 | A44 | A44 | 5282 | 1536 | 640 | 640 | 121 | 768 | 901 |
| A46 Linux x64 | A46 | A46 | 5282 | 1536 | 640 | 640 | 121 | 768 | 901 |
| A47 Linux x64 | A47 | A47 | 8192 | 1536 | 640 | 640 | 121 | 768 | 901 |
| A48 Linux x64 | A48 | A47 | 8192 | 1536 | 640 | 640 | 121 | 768 | 901 |
| A49 qualified staged docs | A49 | A49 | 8192 | 1536 | 640 | 640 | 256 | 768 | 901 |

A45 ships a header declaring A44. A48 declares the same DataChanged marker as
A47. A49 increases RecFileList from 121 to 256 bytes despite several unchanged
record sizes. Archive names, program versions, equal sizes and data-version
markers alone are therefore insufficient to choose arbitrary write offsets.
Per-field checks and native validation remain necessary. None of the newly
compared versions has been enabled for DAT writes.

Vendor files are retained outside this repository and are not relicensed here.
The A49 reference is the already staged qualified header with SHA-256
`4575a20c3cb3c7ec3180e98ab2edbef7ae44da417f870c2e314e1874d1068363`.

| Archive | Archive SHA-256 | records.112 SHA-256 |
| --- | --- | --- |
| 1.12 A45 | `ab72fa09bf2952648edc3823286f4c67e32ba57d582f1d8ef41fc59e7a4cb5b9` | `729879504266147bd32240ddd7e4dced76b68e474ca0c432b8bb707a5b95570b` |
| 1.12 A46 | `21a1dc0e9896b6a2197f72a269bf7b556497b9c74584cb5f9fd00e9338679735` | `838f8edf29fbffaf0b34b31d7d12efd05b5ab639c2ee0c00a3e21acce2d76735` |
| 1.12 A47 | `a0dfa5a695fc05f2c58e085c9abca90dcc05aa58b5468df103e47a94560a5623` | `060731e9a78e4ebafb201842ea21ed184c158fb41c5f530722c6e3e814595b08` |
| 1.12 A48 | `fb427b57d9627ef93008c561df807991bdd288b4a1fc1757dfb5bb5434f286a3` | `7aec6ca491c5868d7c43d33298c910d092e8b2902df02ff634cef6bfe2cb99ef` |
