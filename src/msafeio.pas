unit msafeio;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils;
function PhysicalRoot(const Root:string):string;
procedure RequireStopped(const Root:string);
procedure QualifyWriterBinary(const Root, Version:string);
function CommitConfig(const Root:string; const Expected, Replacement:TBytes):string;
function CommitData(const Root,TargetFile:string; const Expected, Replacement:TBytes):string;
implementation
uses msha256
{$ifdef Linux}, BaseUnix, Unix, mlinuxflags{$endif}
{$ifdef Windows}, Windows, JwaTlHelp32{$endif};

{$ifdef Linux}
function NativeRealPath(Path, Resolved:PChar):PChar; cdecl; external 'c' name 'realpath';
{$endif}
{$ifdef Windows}
function NativeReplaceFile(Existing, Replacement, Backup:PWideChar; Flags:DWORD; Exclude,Reserved:Pointer):BOOL; stdcall;
    external 'kernel32.dll' name 'ReplaceFileW';
function FinalPath(Handle:THandle; Path:PWideChar; Size,Flags:DWORD):DWORD; stdcall;
    external 'kernel32.dll' name 'GetFinalPathNameByHandleW';
function ImagePath(Process:THandle; Flags:DWORD; Path:PWideChar; var Size:DWORD):BOOL; stdcall;
    external 'kernel32.dll' name 'QueryFullProcessImageNameW';
function FromSDDL(Text:PWideChar; Revision:DWORD; out Descriptor:Pointer; Size:Pointer):BOOL; stdcall;
    external 'advapi32.dll' name 'ConvertStringSecurityDescriptorToSecurityDescriptorW';
{$endif}

function PhysicalRoot(const Root:string):string;
{$ifdef Linux}var Buffer:array[0..4095] of Char;{$endif}
{$ifdef Windows}var Handle:THandle; Buffer:array[0..32767] of WideChar; Count:DWORD;{$endif}
begin
    Result:=ExcludeTrailingPathDelimiter(ExpandFileName(Root));
    {$ifdef Linux}
    if NativeRealPath(PChar(Result), @Buffer[0])=nil then
        raise Exception.Create('Cannot resolve the existing root.');
    Result:=StrPas(@Buffer[0]);
    {$endif}
    {$ifdef Windows}
    Handle:=CreateFileW(PWideChar(UTF8Decode(Result)),0,FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,nil,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS,0);
    if Handle=INVALID_HANDLE_VALUE then raise Exception.Create('Cannot resolve the existing directory.');
    try
        Count:=FinalPath(Handle,@Buffer[0],Length(Buffer),0);
        if (Count=0) or (Count>=DWORD(Length(Buffer))) then raise Exception.Create('Cannot resolve the physical directory.');
        Result:=UTF8Encode(UnicodeString(PWideChar(@Buffer[0])));
        if Copy(Result,1,8)='\\?\UNC\' then Result:='\\'+Copy(Result,9,MaxInt)
        else if Copy(Result,1,4)='\\?\' then Delete(Result,1,4);
        Result:=ExcludeTrailingPathDelimiter(Result);
    finally CloseHandle(Handle); end;
    {$endif}
    if not DirectoryExists(Result) then raise Exception.Create('Root directory does not exist.');
end;

procedure QualifyWriterBinary(const Root, Version:string);
var Digest:string;
begin
    {$ifdef Linux}
    Digest:=SHA256File(IncludeTrailingPathDelimiter(Root)+'mystic');
    // ARM candidates are admitted only with the exact vendor binary hash;
    // record layouts and native write tests are documented per architecture.
    if (Version='1.12 A48') and
       ((Digest='e28cb30874a99a51d2bc36d596edf773c88016e4b241dbfb596792bd2a96768d') or
        (Digest='50e68574be0b044fc7a96f7aa57a196ec3450fe4eb4a0a163652f400b7f57bf3') or
        (Digest='db0cedcf3b293f9b8ab007bebe480f118da189a307f0a636b03a5a91201946d8')) then Exit;
    if (Version='1.12 A49') and
       ((Digest='39e47caa92d70e49dd826c074083f4046745ccbe40e5ef89662a98333ee210c3') or
        (Digest='91077e44fa992bbac287d65e471389209a392bc863418886bcff02849e40d74a')) then Exit;
    {$endif}
    {$ifdef Windows}
    Digest:=SHA256File(IncludeTrailingPathDelimiter(Root)+'mystic.exe');
    if (Version='1.12 A49') and ((Digest='e8c70597ba9d3f26e60ba0f1fa448c89a00b65f24cc2be6b179cd9d66e624782') or
       (Digest='7184c66f8b852d5f80fb51b9b91e23a0989b321ffac4aad7fafd4f3fb014c5a7')) then Exit;
    {$endif}
    raise Exception.Create('Native binary is not qualified for writing this record profile.');
end;

procedure RequireStopped(const Root:string);
{$ifdef Linux}
var Search:TSearchRec; Candidate, Target, Link:string;
    ProcessInfo, FileInfo:Stat; Names:array[0..4] of string;
    I,Code,ErrorCode:Integer;
{$endif}
{$ifdef Windows}
var Snapshot, Process:THandle; Entry:TProcessEntry32; Buffer:array[0..32767] of WideChar;
    Count:DWORD; Name, Folder:string;
{$endif}
begin
    {$ifdef Linux}
    Names[0]:='mis'; Names[1]:='mystic'; Names[2]:='mutil'; Names[3]:='mide'; Names[4]:='upgrade';
    Code:=FindFirst('/proc/*',faDirectory,Search);
    try
        while Code=0 do begin
            if (StrToIntDef(Search.Name,0)>0) and (StrToIntDef(Search.Name,0)<>fpGetPid) then begin
                Candidate:='/proc/'+Search.Name+'/exe';
                if fpStat(PChar(Candidate),ProcessInfo)=0 then begin
                    Link:=fpReadLink(Candidate);
                    // Reject any running executable below this root, including
                    // copied or renamed native binaries whose inode differs.
                    if Pos(IncludeTrailingPathDelimiter(Root),Link)=1 then
                        raise Exception.Create('An executable from this root is running; stop it before writing.');
                    for I:=0 to High(Names) do begin
                        Target:=IncludeTrailingPathDelimiter(Root)+Names[I];
                        if (fpStat(PChar(Target),FileInfo)=0) and
                           (FileInfo.st_dev=ProcessInfo.st_dev) and (FileInfo.st_ino=ProcessInfo.st_ino) then
                            raise Exception.Create('MIS/Mystic or a native utility is running; stop it before writing.');
                    end;
                end else begin
                    ErrorCode:=fpGetErrNo;
                    if (ErrorCode=ESysEACCES) or (ErrorCode=ESysEPERM) then
                        raise Exception.Create('Cannot establish process state; use an account with process inspection rights.');
                end;
            end;
            Code:=FindNext(Search);
        end;
    finally FindClose(Search); end;
    {$endif}
    {$ifdef Windows}
    Snapshot:=CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0);
    if Snapshot=INVALID_HANDLE_VALUE then raise Exception.Create('Cannot enumerate processes.');
    try
        FillChar(Entry,SizeOf(Entry),0); Entry.dwSize:=SizeOf(Entry);
        if not Process32First(Snapshot,Entry) then
            raise Exception.Create('Cannot read the process snapshot.');
        repeat
            Name:=LowerCase(StrPas(Entry.szExeFile));
            if (Entry.th32ProcessID=0) or (Entry.th32ProcessID=GetCurrentProcessId) then Continue;
            Process:=OpenProcess($1000,False,Entry.th32ProcessID);
            if Process=0 then begin
                // Protected OS processes may be inaccessible. A native name or
                // an executable present in the target root must fail closed.
                if (Name='mis.exe') or (Name='mystic.exe') or
                   (Name='mutil.exe') or (Name='mide.exe') or
                   (Name='upgrade.exe') or
                   FileExists(IncludeTrailingPathDelimiter(Root)+Name) then
                    raise Exception.Create('Cannot inspect a candidate Mystic process.');
                Continue;
            end;
            try
                Count:=Length(Buffer);
                if not ImagePath(Process,0,@Buffer[0],Count) then begin
                    if (Name='mis.exe') or (Name='mystic.exe') or
                       (Name='mutil.exe') or (Name='mide.exe') or
                       (Name='upgrade.exe') or
                       FileExists(IncludeTrailingPathDelimiter(Root)+Name) then
                        raise Exception.Create('Cannot determine a candidate process path.');
                    // System pseudo-processes can have no user-mode image.
                    Continue;
                end;
                Folder:=ExcludeTrailingPathDelimiter(ExtractFilePath(UTF8Encode(UnicodeString(PWideChar(@Buffer[0])))));
                try
                    Folder:=PhysicalRoot(Folder);
                except
                    // Hosted runners can retain processes whose unrelated
                    // working image directory has already been removed.
                    if (Name='mis.exe') or (Name='mystic.exe') or
                       (Name='mutil.exe') or (Name='mide.exe') or
                       (Name='upgrade.exe') or
                       FileExists(IncludeTrailingPathDelimiter(Root)+Name) or
                       SameText(Folder,Root) or
                       SameText(Copy(Folder,1,Length(IncludeTrailingPathDelimiter(Root))),IncludeTrailingPathDelimiter(Root)) then
                        raise;
                    Continue;
                end;
                if SameText(Folder,Root) or
                   SameText(Copy(Folder,1,Length(IncludeTrailingPathDelimiter(Root))),IncludeTrailingPathDelimiter(Root)) then
                    raise Exception.Create('An executable from this root is running; stop it before writing.');
            finally CloseHandle(Process); end;
        until not Process32Next(Snapshot,Entry);
        if GetLastError<>ERROR_NO_MORE_FILES then
            raise Exception.Create('Process enumeration ended unexpectedly.');
    finally CloseHandle(Snapshot); end;
    {$endif}
end;

procedure SavePrivate(const Path:string; const Data:TBytes);
{$ifdef Linux}var FD:LongInt; Count,Offset:ssize_t;{$endif}
{$ifdef Windows}var Handle:THandle; Descriptor:Pointer; Attributes:TSecurityAttributes; Written:DWORD;{$endif}
begin
    {$ifdef Linux}
    FD:=fpOpen(PChar(Path),O_WRONLY or O_CREAT or O_EXCL or NativeNoFollowFlag,&600);
    if FD<0 then raise Exception.Create('Cannot create a new protected file.');
    try
        Offset:=0;
        while Offset<Length(Data) do begin
            Count:=fpWrite(FD,Data[Offset],Length(Data)-Offset);
            if Count<=0 then raise Exception.Create('Protected file write failed.');
            Inc(Offset,Count);
        end;
        if fpFsync(FD)<>0 then raise Exception.Create('Protected file synchronization failed.');
    finally fpClose(FD); end;
    {$endif}
    {$ifdef Windows}
    Descriptor:=nil;
    if not FromSDDL('D:P(A;;FA;;;OW)(A;;FA;;;SY)(A;;FA;;;BA)',1,Descriptor,nil) then
        raise Exception.Create('Cannot create a private security descriptor.');
    try
        FillChar(Attributes,SizeOf(Attributes),0); Attributes.nLength:=SizeOf(Attributes); Attributes.lpSecurityDescriptor:=Descriptor;
        Handle:=CreateFileW(PWideChar(UTF8Decode(Path)),GENERIC_WRITE,0,@Attributes,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,0);
        if Handle=INVALID_HANDLE_VALUE then raise Exception.Create('Cannot create a protected new file.');
        try
            if Length(Data)>0 then begin
                if not WriteFile(Handle,Data[0],Length(Data),Written,nil) or (Written<>DWORD(Length(Data))) then
                    raise Exception.Create('Protected file write failed.');
            end;
            if not FlushFileBuffers(Handle) then
                raise Exception.Create('Protected file synchronization failed.');
        finally CloseHandle(Handle); end;
    finally LocalFree(HLOCAL(Descriptor)); end;
    {$endif}
end;

function ReadAll(const Path:string):TBytes;
var Stream:TFileStream;
begin
    Result:=nil; Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyNone);
    try
        SetLength(Result,Stream.Size);
        if Length(Result)>0 then Stream.ReadBuffer(Result[0],Length(Result));
    finally Stream.Free; end;
end;

{$ifdef Linux}
function ReadLocked(FD:LongInt):TBytes;
var Size,Offset,Count:Int64;
begin
    Result:=nil; Size:=fpLSeek(FD,0,SEEK_END);
    if (Size<0) or (Size>1048576) or (fpLSeek(FD,0,SEEK_SET)<0) then
        raise Exception.Create('Cannot read the locked DAT descriptor.');
    SetLength(Result,Size); Offset:=0;
    while Offset<Size do begin
        Count:=fpRead(FD,Result[Offset],Size-Offset);
        if Count<=0 then raise Exception.Create('Locked DAT read failed.');
        Inc(Offset,Count);
    end;
end;
{$endif}

{$ifdef Linux}
procedure SyncDirectory(const Path:string);
var FD:LongInt;
begin
    FD:=fpOpen(PChar(Path),O_RDONLY or NativeDirectoryFlag);
    if FD<0 then raise Exception.Create('Cannot open directory for synchronization.');
    try
        if fpFsync(FD)<>0 then raise Exception.Create('Directory synchronization failed. Backup retained.');
    finally fpClose(FD); end;
end;
{$endif}

function CommitData(const Root,TargetFile:string; const Expected, Replacement:TBytes):string;
var Target,LockPath,Temporary,BackupDirectory,Token:string; Current:TBytes; ID:TGUID;
{$ifdef Linux}var LockFD,DirectoryFD,TargetFD:LongInt; Original,FileInfo:Stat;{$endif}
{$ifdef Windows}var LockHandle,TargetHandle:THandle; OriginalInfo,CurrentInfo:TByHandleFileInformation;{$endif}
begin
    Result:=''; Temporary:='';
    Target:=IncludeTrailingPathDelimiter(PhysicalRoot(ExtractFilePath(ExpandFileName(TargetFile))))+ExtractFileName(TargetFile);
    {$ifdef Windows}
    if CompareText(Copy(Target,1,Length(IncludeTrailingPathDelimiter(Root))),IncludeTrailingPathDelimiter(Root))<>0 then
    {$else}
    if Copy(Target,1,Length(IncludeTrailingPathDelimiter(Root)))<>IncludeTrailingPathDelimiter(Root) then
    {$endif}
        raise Exception.Create('DAT target must remain inside the root.');
    if (ExtractFileName(Target)<>'mystic.dat') and (ExtractFileName(Target)<>'servers.dat') and (ExtractFileName(Target)<>'event.dat') then
        raise Exception.Create('Unsupported DAT target.');
    if (Length(Expected)<>Length(Replacement)) and (ExtractFileName(Target)<>'event.dat') then
        raise Exception.Create('Record size must not change.');
    if (ExtractFileName(Target)='event.dat') and ((Length(Replacement) mod 640<>0) or
       (Length(Replacement)>1048576)) then
        raise Exception.Create('Event data must contain complete bounded records.');
    LockPath:=IncludeTrailingPathDelimiter(Root)+'.mdatmod.lock';
    {$ifdef Linux}
    if (fpLStat(PChar(Target),Original)<>0) or not FPS_ISREG(Original.st_mode) then
        raise Exception.Create('DAT must be a regular file, not a symlink.');
    LockFD:=fpOpen(PChar(LockPath),O_RDWR or O_CREAT or NativeNoFollowFlag,&600);
    if LockFD<0 then raise Exception.Create('Cannot create writer lock.');
    if fpFlock(LockFD,LOCK_EX or LOCK_NB)<>0 then begin fpClose(LockFD); raise Exception.Create('Another writer holds the root lock.'); end;
    TargetFD:=fpOpen(PChar(Target),O_RDWR or NativeNoFollowFlag);
    if TargetFD<0 then begin fpClose(LockFD); raise Exception.Create('Cannot exclusively open the DAT target.'); end;
    if fpFlock(TargetFD,LOCK_EX or LOCK_NB)<>0 then begin fpClose(TargetFD); fpClose(LockFD); raise Exception.Create('Another process locks the DAT target.'); end;
    {$endif}
    {$ifdef Windows}
    if GetFileAttributesW(PWideChar(UTF8Decode(Target))) and FILE_ATTRIBUTE_REPARSE_POINT<>0 then
        raise Exception.Create('DAT must not be a reparse point.');
    LockHandle:=CreateFileW(PWideChar(UTF8Decode(LockPath)),GENERIC_READ or GENERIC_WRITE,0,nil,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL or $00200000,0);
    if LockHandle=INVALID_HANDLE_VALUE then raise Exception.Create('Another writer holds the root lock or the lock is unavailable.');
    {$endif}
    {$ifdef Windows}
    if not GetFileInformationByHandle(LockHandle,CurrentInfo) or
       (CurrentInfo.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT<>0) then begin
        CloseHandle(LockHandle);
        raise Exception.Create('Writer lock must not be a reparse point.');
    end;
    {$endif}
    {$ifdef Windows}
    // Deny writes while allowing ReplaceFileW to atomically replace this path.
    // Keep the original handle alive until verification finishes.
    TargetHandle:=CreateFileW(PWideChar(UTF8Decode(Target)),GENERIC_READ,
        FILE_SHARE_READ or FILE_SHARE_DELETE,nil,OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL or $00200000,0);
    if TargetHandle=INVALID_HANDLE_VALUE then begin
        CloseHandle(LockHandle);
        raise Exception.Create('Cannot acquire the DAT read/replace guard.');
    end;
    {$endif}
    try
        RequireStopped(Root);
        {$ifdef Linux}Current:=ReadLocked(TargetFD);{$else}
        if not GetFileInformationByHandle(TargetHandle,OriginalInfo) or
           (OriginalInfo.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT<>0) then
            raise Exception.Create('Cannot establish regular DAT identity.');
        Current:=ReadAll(Target);
        {$endif}
        if SHA256Bytes(Current)<>SHA256Bytes(Expected) then raise Exception.Create('DAT changed after inspection; write refused.');
        BackupDirectory:=IncludeTrailingPathDelimiter(Root)+'backups';
        if not DirectoryExists(BackupDirectory) and not CreateDir(BackupDirectory) then raise Exception.Create('Cannot create backup directory.');
        {$ifdef Linux}
        if (fpLStat(PChar(BackupDirectory),FileInfo)<>0) or not FPS_ISDIR(FileInfo.st_mode) then
            raise Exception.Create('Backup directory must not be a symlink.');
        {$endif}
        {$ifdef Windows}
        if GetFileAttributesW(PWideChar(UTF8Decode(BackupDirectory))) and FILE_ATTRIBUTE_REPARSE_POINT<>0 then
            raise Exception.Create('Backup directory must not be a reparse point.');
        {$endif}
        if CreateGUID(ID)<>0 then raise Exception.Create('Cannot allocate a unique transaction ID.');
        Token:=GUIDToString(ID); Delete(Token,1,1); Delete(Token,Length(Token),1);
        Result:=IncludeTrailingPathDelimiter(BackupDirectory)+'mdatmod-'+ChangeFileExt(ExtractFileName(Target),'')+'-'+Token+'.dat';
        SavePrivate(Result,Expected);
        SavePrivate(Result+'.sha256',BytesOf(SHA256Bytes(Expected)+'  '+ExtractFileName(Result)+LineEnding));
        SavePrivate(Result+'.target',BytesOf(Copy(Target,Length(IncludeTrailingPathDelimiter(Root))+1,MaxInt)+LineEnding));
        {$ifdef Linux}
        DirectoryFD:=fpOpen(PChar(BackupDirectory),O_RDONLY or NativeDirectoryFlag);
        if DirectoryFD<0 then raise Exception.Create('Cannot open backup directory for synchronization.');
        try
            if fpFsync(DirectoryFD)<>0 then raise Exception.Create('Backup directory synchronization failed.');
        finally fpClose(DirectoryFD); end;
        {$endif}
        {$ifdef Linux}SyncDirectory(Root);{$endif}
        Temporary:=IncludeTrailingPathDelimiter(Root)+'.mdatmod-'+Token+'.new';
        SavePrivate(Temporary,Replacement);
        {$ifdef Linux}
        if fpChown(PChar(Temporary),Original.st_uid,Original.st_gid)<>0 then raise Exception.Create('Cannot preserve DAT ownership.');
        if fpChmod(PChar(Temporary),Original.st_mode and &777)<>0 then raise Exception.Create('Cannot preserve DAT permissions.');
        {$endif}
        RequireStopped(Root);
        {$ifdef Linux}
        if (fpStat(PChar(Target),FileInfo)<>0) or (FileInfo.st_dev<>Original.st_dev) or (FileInfo.st_ino<>Original.st_ino) then
            raise Exception.Create('DAT identity changed before commit.');
        if SHA256Bytes(ReadLocked(TargetFD))<>SHA256Bytes(Expected) then
        {$else}
        if not GetFileInformationByHandle(TargetHandle,CurrentInfo) or
           (CurrentInfo.nFileIndexHigh<>OriginalInfo.nFileIndexHigh) or
           (CurrentInfo.nFileIndexLow<>OriginalInfo.nFileIndexLow) then
            raise Exception.Create('DAT identity changed before commit.');
        if SHA256File(Target)<>SHA256Bytes(Expected) then
        {$endif}
            raise Exception.Create('DAT changed before commit; write refused.');
        {$ifdef Linux}
        if fpRename(PChar(Temporary),PChar(Target))<>0 then raise Exception.Create('Atomic DAT replacement failed.');
        Temporary:='';
        DirectoryFD:=fpOpen(PChar(ExtractFilePath(Target)),O_RDONLY or NativeDirectoryFlag);
        if DirectoryFD<0 then raise Exception.Create('Cannot synchronize the root directory. Backup retained.');
        try
            if fpFsync(DirectoryFD)<>0 then raise Exception.Create('Directory synchronization failed. Backup retained.');
        finally fpClose(DirectoryFD); end;
        SyncDirectory(Root);
        {$endif}
        {$ifdef Windows}
        if not NativeReplaceFile(PWideChar(UTF8Decode(Target)),PWideChar(UTF8Decode(Temporary)),nil,0,nil,nil) then
            raise Exception.Create('Atomic DAT replacement failed. Backup retained.');
        Temporary:='';
        {$endif}
        if SHA256File(Target)<>SHA256Bytes(Replacement) then raise Exception.Create('Post-write verification failed. Backup retained.');
    finally
        if (Temporary<>'') and FileExists(Temporary) then SysUtils.DeleteFile(Temporary);
        {$ifdef Linux}fpClose(TargetFD); fpClose(LockFD);{$endif}
        {$ifdef Windows}CloseHandle(TargetHandle); CloseHandle(LockHandle);{$endif}
    end;
end;
function CommitConfig(const Root:string; const Expected, Replacement:TBytes):string;
begin
    Result:=CommitData(Root,IncludeTrailingPathDelimiter(Root)+'mystic.dat',Expected,Replacement);
end;
end.
