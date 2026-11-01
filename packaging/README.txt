mdatmod - qualified offline Mystic DAT tool
===========================================

Reads and writes public fields of Mystic 1.12 A49 DAT files through
validated record profiles. Unknown versions and layouts are refused.

Requirements
------------
- Mystic 1.12 A49 installation with its matching docs/records.112
- MIS, Mystic, MUTIL, MIDE and UPGRADE stopped while a write is applied
- Inspection archives: Linux amd64/arm64/armhf or Windows x86/x64
- Qualified writes: Linux amd64 A48/A49, arm64 A48, armhf A48/A49; Windows x86/x64 A49

Usage
-----
  mdatmod inspect ROOT
  mdatmod profile ROOT
  mdatmod get ROOT FIELD
  mdatmod set ROOT FIELD VALUE [--apply]
  mdatmod set-config ROOT REQUEST.ini [--apply]
  mdatmod set-server ROOT PROTOCOL REQUEST.ini [--apply]
  mdatmod disable-servers ROOT [--apply]
  mdatmod ban-event ROOT REQUEST.ini [--apply]
  mdatmod restore ROOT BACKUP [--apply]
  mdatmod check-offline ROOT
  mdatmod --hash FILE
  mdatmod --self-test

Without --apply every write command only prints the plan and changes
nothing. With --apply the tool checks the binary hash, record profile and
process state, takes an exclusive lock, writes a private backup with SHA-256
and target reference, replaces the file atomically and verifies the result.
restore accepts only backups created by this tool.

ROOT is the Mystic installation directory. REQUEST.ini contains one
[Fields] section with public field names; values are printable ASCII.

Private fields, unknown profiles, overlong values, running instances and
symlinked DAT files are refused. There is no support for editing a running
production BBS: plan a maintenance window and stop the services first.

Extract the archive beside Mystic, for example /opt/mystic or C:\Mystic.
No installer, service or PATH change is performed.

License: GPL-3.0-only
Source:  https://github.com/geosone/mdatmod

Locking and qualification
-------------------------
Windows holds a read/replace handle denying foreign write handles. Linux uses
flock on the original inode. The tool cannot interlock with a future service
start or a privileged filesystem path swap: disable automatic restarts and
keep the BBS offline throughout maintenance. Renamed executables inside the
root are detected, except for the current mdatmod process itself.

Native release tests cover config/server/event writes, unchanged bytes,
checksummed backups and restore, empty event files, invalid fields, foreign
file locks and native/renamed processes. ARM native write qualification covers Debian 12/13, with A48 on arm64
and A48/A49 on armhf. Other vendor binaries remain refused. Vendor fixtures are downloaded for tests, never shipped.

ARM syscall compatibility: FPC 3.2.2 supplies x86 directory/no-follow open
flags on ARM. mdatmod uses the measured ARM/AArch64 ABI constants and tests
their actual kernel behavior. Vendor ARM32 executables require the legacy
/lib/ld-linux.so.3 loader name; the qualification image provides an alias to
the hard-float loader inside disposable containers only. See the source
qualification report for exact vendor hashes and the six native test runs.
