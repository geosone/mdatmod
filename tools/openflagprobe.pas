program OpenFlagProbe;
{$mode objfpc}{$H+}
uses SysUtils, Classes, BaseUnix, mlinuxflags;
var Root,FilePath,LinkPath:string; Stream:TFileStream; FD:LongInt; Info:Stat;
begin
    if ParamCount<>1 then raise Exception.Create('Supply a fresh test directory.');
    Root:=ExpandFileName(ParamStr(1));
    if DirectoryExists(Root) or FileExists(Root) then
        raise Exception.Create('Test directory already exists.');
    if not CreateDir(Root) then raise Exception.Create('Cannot create test directory.');
    FilePath:=IncludeTrailingPathDelimiter(Root)+'regular';
    LinkPath:=IncludeTrailingPathDelimiter(Root)+'link';
    try
        FD:=fpOpen(PChar(Root),O_RDONLY or NativeDirectoryFlag);
        if FD<0 then raise Exception.Create('Kernel rejected the directory open flag.');
        try
            if (fpFStat(FD,Info)<>0) or not FPS_ISDIR(Info.st_mode) then
                raise Exception.Create('Directory flag did not open a directory.');
        finally fpClose(FD); end;
        Stream:=TFileStream.Create(FilePath,fmCreate); Stream.Free;
        if fpSymlink(PChar(FilePath),PChar(LinkPath))<>0 then
            raise Exception.Create('Cannot create the fixture symlink.');
        FD:=fpOpen(PChar(LinkPath),O_RDONLY or NativeNoFollowFlag);
        if FD>=0 then begin
            fpClose(FD);
            raise Exception.Create('Kernel followed the symlink despite the no-follow flag.');
        end;
        if fpGetErrNo<>ESysELOOP then
            raise Exception.Create('Symlink refusal returned an unexpected error.');
        Writeln('DirectoryFlag=',NativeDirectoryFlag);
        Writeln('NoFollowFlag=',NativeNoFollowFlag);
        Writeln('Status=PASS');
    finally
        if FileExists(LinkPath) then SysUtils.DeleteFile(LinkPath);
        if FileExists(FilePath) then SysUtils.DeleteFile(FilePath);
        RemoveDir(Root);
    end;
end.
