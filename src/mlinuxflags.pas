unit mlinuxflags;
{$mode objfpc}{$H+}
interface
uses BaseUnix;
// Linux ARM/AArch64 bits/fcntl.h defines O_DIRECTORY=040000 and
// O_NOFOLLOW=0100000 (octal). FPC 3.2.2 BaseUnix exposes the x86 values
// 0200000/0400000 on these targets. Those are different kernel operations;
// use the measured architecture ABI and exercise it in openflagprobe.pas.
{$if defined(CPUARM) or defined(CPUAARCH64)}
const
    NativeDirectoryFlag = &40000;
    NativeNoFollowFlag = &100000;
{$else}
const
    NativeDirectoryFlag = O_DIRECTORY;
    NativeNoFollowFlag = O_NOFOLLOW;
{$endif}
implementation
end.
