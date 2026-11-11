program mdatmod;

{$mode objfpc}{$H+}

uses Classes, SysUtils, Sockets, msha256, mprofiles, msafeio, mrequest, marchive, mrecords;

procedure Usage;
begin
    Writeln('mdatmod 0.6.1 - qualified offline Mystic DAT tool');
    Writeln('  mdatmod --help | -h | /h | /?');
    Writeln('  mdatmod inspect ROOT');
    Writeln('  mdatmod get ROOT FIELD');
    Writeln('  mdatmod set ROOT FIELD VALUE [--apply]');
    Writeln('  mdatmod restore ROOT BACKUP [--apply]');
    Writeln('  mdatmod profile ROOT');
    Writeln('  mdatmod check-offline ROOT');
    Writeln('  mdatmod set-config ROOT REQUEST.ini [--apply]');
    Writeln('  mdatmod set-server ROOT PROTOCOL REQUEST.ini [--apply]');
    Writeln('  mdatmod disable-servers ROOT [--apply]');
    Writeln('  mdatmod ban-event ROOT REQUEST.ini [--apply]');
    Writeln('  mdatmod get-archive ROOT EXT OSTYPE');
    Writeln('  mdatmod set-archive ROOT EXT OSTYPE REQUEST.ini [--apply]');
    Writeln('  mdatmod schema ROOT FILE');
    Writeln('  mdatmod list ROOT FILE [FIELD ...]');
    Writeln('  mdatmod set-record ROOT FILE REQUEST.ini [--apply]');
    Writeln('OSTYPE is Windows, Linux, macOS or All; archive records need A49.');
    Writeln('FILE is a Mystic DAT name such as event.dat; its layout comes from records.112.');
    Writeln('  mdatmod --hash FILE');
    Writeln('  mdatmod --self-test');
    Writeln('Writes require a qualified native binary, stopped MIS/Mystic and --apply.');
end;

procedure SelfTest;
begin
    if SHA256Bytes(BytesOf('')) <> 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' then
        raise Exception.Create('SHA-256 empty-message self-test failed.');
    if SHA256Bytes(BytesOf('abc')) <> 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' then
        raise Exception.Create('SHA-256 short-message self-test failed.');
    if SHA256Bytes(BytesOf(StringOfChar('a', 1000000))) <>
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0' then
        raise Exception.Create('SHA-256 multiblock self-test failed.');
    Writeln('PASS SHA-256 empty, abc and million-a vectors.');
end;

function ReadConfig(const Root: string; Profile: Integer): TBytes;
var
    Stream: TFileStream;
    Version: string;
    I: Integer;
begin
    Result := nil;
    Stream := TFileStream.Create(IncludeTrailingPathDelimiter(Root) + 'mystic.dat',
        fmOpenRead or fmShareDenyNone);
    try
        if Stream.Size <> Profiles[Profile].ConfigSize then
            raise Exception.Create('DAT size does not match the measured profile.');
        SetLength(Result, Stream.Size);
        Stream.ReadBuffer(Result[0], Length(Result));
    finally
        Stream.Free;
    end;
    if Result[0] <> 8 then
        raise Exception.Create('Unknown DAT data-version header.');
    Version := '';
    for I := 1 to 8 do
        Version := Version + Chr(Result[I]);
    if Version <> Profiles[Profile].DataVersion then
        raise Exception.Create('DAT data-version marker does not match its developer records.');
end;

function IdentifyProfile(const Root: string): Integer;
var
    Docs, Digest: string;
    I: Integer;
begin
    Docs := IncludeTrailingPathDelimiter(Root) + 'docs' + PathDelim + 'records.112';
    if not FileExists(Docs) then Docs:=IncludeTrailingPathDelimiter(Root)+'records.112';
    Digest := SHA256File(Docs);
    for I := Low(Profiles) to High(Profiles) do
        if Digest = Profiles[I].DocsHash then
            Exit(I);
    raise Exception.Create('Unknown developer records; no field offsets were used.');
end;

function SafeString(const Data: TBytes; const Field: TField): string;
var
    Count, I: Integer;
    Value: Byte;
begin
    if (Field.Offset < 0) or (Field.Offset + Field.Maximum >= Length(Data)) then
        raise Exception.Create('Field lies outside the qualified record.');
    Count := Data[Field.Offset];
    if Count > Field.Maximum then
        raise Exception.Create('Invalid Pascal short-string length.');
    Result := '';
    for I := 1 to Count do
    begin
        Value := Data[Field.Offset + I];
        // Avoid interpreting terminal controls or guessing the stored code page.
        if (Value >= 32) and (Value <= 126) then
            Result := Result + Chr(Value)
        else
            Result := Result + '\x' + IntToHex(Value, 2);
    end;
end;

// A49 RecConfig, measured against the hashed vendor records.112 by
// writerlayoutprobe.pas. Each field is one Byte (one-byte total reservation,
// no string length prefix). Native A49 -cfg round trips qualified the enums.
function FindCodePageField(Profile: Integer; const Name: string; out Offset: Integer): Boolean;
begin
    Result := False;
    if Profiles[Profile].Name <> '1.12 A49' then
        Exit;
    if SameText(Name, 'LocalCodePage') then
        Offset := 1247
    else if SameText(Name, 'StartCodePage') then
        Offset := 1450
    else if SameText(Name, 'AskCodePage') then
        Offset := 2007
    else
        Exit;
    Result := True;
end;

function CodePageName(const Name: string; Value: Byte): string;
begin
    if SameText(Name, 'AskCodePage') then
    begin
        case Value of
            0: Exit('Detect');
            1: Exit('Ask');
            2: Exit('CP437');
            3: Exit('UTF8');
        end;
    end
    else
    begin
        case Value of
            0: Exit('CP437');
            1: Exit('UTF8');
        end;
    end;
    raise Exception.Create('Unknown native codepage value.');
end;

function CodePageValue(const Name, Value: string): Byte;
var
    I, Maximum: Integer;
begin
    Maximum := 1;
    if SameText(Name, 'AskCodePage') then
        Maximum := 3;
    for I := 0 to Maximum do
        if SameText(Value, CodePageName(Name, I)) then
            Exit(I);
    raise Exception.Create('Use a symbolic codepage name, not an unqualified numeric enum.');
end;

// A49 vendor RecConfig has four consecutive RecLogRoller records, 35 bytes
// each. Verified by tools/writerlayoutprobe.pas against the hashed records.112.
// DateFmt is at record-relative zero-based offset 9: String[25] reserves
// 26 bytes (one length byte plus 25 payload bytes). No other log field changes.
function FindLogDateField(Profile: Integer; const Name: string; out Field: TField): Boolean;
var
    Base: Integer;
begin
    Result := False;
    if Profiles[Profile].Name <> '1.12 A49' then
        Exit;
    if SameText(Name, 'MISLogDateFormat') then
        Base := 4573
    else if SameText(Name, 'NodeLogDateFormat') then
        Base := 4608
    else if SameText(Name, 'PollLogDateFormat') then
        Base := 4643
    else if SameText(Name, 'QWKLogDateFormat') then
        Base := 4678
    else
        Exit;
    Field.Name := Name;
    Field.Offset := Base + 9;
    Field.Maximum := 25;
    Result := True;
end;

// A49 vendor RecLogRoller.Files is a little-endian Word at record-relative
// zero-based offset 2, reserving exactly two bytes. Record bases and storage
// widths are checked by writerlayoutprobe against the hashed records.112.
function FindLogFilesField(Profile: Integer; const Name: string; out Field: TField): Boolean;
var
    Base: Integer;
begin
    Result := False;
    if Profiles[Profile].Name <> '1.12 A49' then
        Exit;
    if SameText(Name, 'MISLogFiles') then
        Base := 4573
    else if SameText(Name, 'NodeLogFiles') then
        Base := 4608
    else if SameText(Name, 'PollLogFiles') then
        Base := 4643
    else if SameText(Name, 'QWKLogFiles') then
        Base := 4678
    else
        Exit;
    Field.Name := Name;
    Field.Offset := Base + 2;
    Field.Maximum := 2;
    Result := True;
end;

function ReadRaw(const Path:string):TBytes;
var Stream:TFileStream;
begin
    Result:=nil;
    Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyNone);
    try
        if Stream.Size>16777216 then raise Exception.Create('File exceeds the supported DAT size.');
        SetLength(Result,Stream.Size);
        if Length(Result)>0 then Stream.ReadBuffer(Result[0],Length(Result));
    finally Stream.Free; end;
end;


// Generic records.112 support. The developer record source is the one whose
// SHA-256 IdentifyProfile accepted, so only a known vendor layout is parsed.
function RecordsPath(const Root: string): string;
begin
    Result := IncludeTrailingPathDelimiter(Root) + 'docs' + PathDelim + 'records.112';
    if not FileExists(Result) then
        Result := IncludeTrailingPathDelimiter(Root) + 'records.112';
end;

function LoadCatalog(const Root: string): TRecordCatalog;
begin
    Result := TRecordCatalog.Create(SizeOf(Pointer));
    try
        {$ifdef Windows}
        Result.LoadFromFile(RecordsPath(Root), ['WINDOWS']);
        {$else}
        Result.LoadFromFile(RecordsPath(Root), ['LINUX']);
        {$endif}
    except
        Result.Free;
        raise;
    end;
end;

// Looks up FILE, refuses personal data and returns its record type and path.
// DataPath (RecConfig offset 98, String[80]) must be absolute.
function ResolveRecordFile(const Root, Name: string; Catalog: TRecordCatalog;
    const Config: TBytes; out Item: TDataFile; out Path: string): TRecordType;
var
    Directory: string;
begin
    if not FindDataFile(Name, Item) then
        raise Exception.Create('Unknown Mystic DAT file; see --help.');
    if Item.Personal then
        raise Exception.Create(Item.FileName + ' holds personal data and is not accessible.');
    Result := Catalog.Find(Item.TypeName);
    if (Result = nil) or not Result.Storable or (Result.Size <= 0) then
        raise Exception.Create('records.112 has no storable ' + Item.TypeName + '.');
    if Item.InRoot then
        Path := IncludeTrailingPathDelimiter(Root) + Item.FileName
    else
    begin
        Directory := GetString(Config, 98, 80);
        {$ifdef Windows}
        if ExtractFileDrive(Directory) = '' then
        {$else}
        if (Directory = '') or (Directory[1] <> '/') then
        {$endif}
            raise Exception.Create('Native data directory must be absolute.');
        Path := IncludeTrailingPathDelimiter(PhysicalRoot(Directory)) + Item.FileName;
    end;
end;

function GenericRecordSize(const Root, Name: string): Integer;
var
    Catalog: TRecordCatalog;
    Item: TDataFile;
    RecordType: TRecordType;
    Path: string;
    Config: TBytes;
begin
    Catalog := LoadCatalog(Root);
    try
        Config := ReadConfig(Root, IdentifyProfile(Root));
        RecordType := ResolveRecordFile(Root, Name, Catalog, Config, Item, Path);
        Result := RecordType.Size;
    finally
        Catalog.Free;
    end;
end;

procedure WriteCommand;
var Root,FieldName,Value,Backup,Checksum,Command,TargetPath,Relative:string;
    Profile,Index,I,Size:Integer;
    Generic:Boolean;
    Original,Replacement,ChecksumBytes:TBytes;
    Field:TField;
    Apply:Boolean;
begin
    Command:=LowerCase(ParamStr(1));
    if Command='set' then begin
        if (ParamCount<>4) and ((ParamCount<>5) or (ParamStr(5)<>'--apply')) then
            raise Exception.Create('Use set ROOT FIELD VALUE [--apply].');
        Apply:=ParamCount=5;
    end else begin
        if (ParamCount<>3) and ((ParamCount<>4) or (ParamStr(4)<>'--apply')) then
            raise Exception.Create('Use restore ROOT BACKUP [--apply].');
        Apply:=ParamCount=4;
    end;
    Root:=PhysicalRoot(ParamStr(2));
    Profile:=IdentifyProfile(Root);
    QualifyWriterBinary(Root,Profiles[Profile].Name);
    Original:=ReadConfig(Root,Profile);
    TargetPath:=IncludeTrailingPathDelimiter(Root)+'mystic.dat';
    Generic:=False;
    Size:=0;
    if Command='set' then begin
        FieldName:=ParamStr(3); Value:=ParamStr(4); Index:=-1;
        for I:=0 to Profiles[Profile].FieldCount-1 do
            if SameText(FieldName,Profiles[Profile].Fields[I].Name) then Index:=I;
        if Index<0 then raise Exception.Create('Field is not in the public configuration allowlist.');
        Field:=Profiles[Profile].Fields[Index];
        if Length(Value)>Field.Maximum then raise Exception.Create('Value exceeds the native Pascal string capacity.');
        for I:=1 to Length(Value) do
            if (Ord(Value[I])<32) or (Ord(Value[I])>126) then
                raise Exception.Create('Current string writes accept printable ASCII only; no code-page conversion is guessed.');
        if (Field.Offset<0) or (Field.Offset+Field.Maximum>=Length(Original)) then
            raise Exception.Create('Field lies outside the qualified record.');
        Replacement:=Copy(Original);
        // String[N] has a length byte followed by exactly N payload bytes.
        // Only this measured field is changed; all unrelated bytes survive.
        FillChar(Replacement[Field.Offset],Field.Maximum+1,0);
        Replacement[Field.Offset]:=Length(Value);
        for I:=1 to Length(Value) do Replacement[Field.Offset+I]:=Ord(Value[I]);
    end else begin
        Backup:=ExpandFileName(ParamStr(3));
        if Pos(IncludeTrailingPathDelimiter(Root)+'backups'+PathDelim,Backup)<>1 then
            raise Exception.Create('Restore accepts only a backup below this root backups directory.');
        ChecksumBytes:=ReadRaw(Backup+'.sha256');
        SetString(Checksum,PChar(ChecksumBytes),Length(ChecksumBytes));
        Replacement:=ReadRaw(Backup);
        if (Length(Checksum)<64) or (Copy(Checksum,1,64)<>SHA256Bytes(Replacement)) then
            raise Exception.Create('Backup checksum verification failed.');
        if FileExists(Backup+'.target') then begin
            ChecksumBytes:=ReadRaw(Backup+'.target');
            SetString(Relative,PChar(ChecksumBytes),Length(ChecksumBytes)); Relative:=Trim(Relative);
            if (Relative='') or (Pos('..',Relative)>0) then raise Exception.Create('Invalid relative backup target.');
            TargetPath:=IncludeTrailingPathDelimiter(Root)+Relative;
            TargetPath:=IncludeTrailingPathDelimiter(PhysicalRoot(ExtractFilePath(TargetPath)))+ExtractFileName(TargetPath);
            if Pos(IncludeTrailingPathDelimiter(Root),TargetPath)<>1 then raise Exception.Create('Backup target escapes the root.');
            Original:=ReadRaw(TargetPath);
        end;
        if ExtractFileName(TargetPath)='mystic.dat' then begin
            if (Length(Replacement)<>Profiles[Profile].ConfigSize) or (Replacement[0]<>8) then
                raise Exception.Create('Backup layout does not match the qualified record.');
            SetString(Value,PChar(@Replacement[1]),8);
            if Value<>Profiles[Profile].DataVersion then raise Exception.Create('Backup data version does not match.');
        end else if ExtractFileName(TargetPath)='servers.dat' then begin
            if (Length(Replacement) mod 384<>0) or (Length(Replacement)<>Length(Original)) then raise Exception.Create('Unknown server backup layout.');
        end else if ExtractFileName(TargetPath)='event.dat' then begin
            if Length(Replacement) mod 640<>0 then raise Exception.Create('Unknown event backup layout.');
        end else if ExtractFileName(TargetPath)='archive.dat' then begin
            // Restoring may remove records an earlier set-archive appended.
            if Length(Replacement) mod ArchiveRecordSize<>0 then
                raise Exception.Create('Unknown archive backup layout.');
        end else begin
            // Any other records.112 file: whole records of its type.
            Size:=GenericRecordSize(Root,ExtractFileName(TargetPath));
            if Length(Replacement) mod Size<>0 then raise Exception.Create('Unknown backup layout.');
            Generic:=True;
        end;
    end;
    if SHA256Bytes(Original)=SHA256Bytes(Replacement) then begin
        Writeln('Action=Unchanged'); Exit;
    end;
    if not Apply then begin
        Writeln('Action=Plan');
        Writeln('Operation=',Command);
        Writeln('Profile=',Profiles[Profile].Name);
        Writeln('ConfigSHA256=',SHA256Bytes(Original));
        Writeln('BackupRequired=true');
        Writeln('RequiresStopped=true');
        Exit;
    end;
    if Generic then
        Backup:=CommitRecords(Root,TargetPath,Original,Replacement,Size)
    else
        Backup:=CommitData(Root,TargetPath,Original,Replacement);
    Writeln('Action=Applied');
    Writeln('Operation=',Command);
    Writeln('Backup=',Backup);
    Writeln('ConfigSHA256=',SHA256Bytes(Replacement));
end;

procedure BatchCommand;
var Root,Command,RequestPath,Key,Value,Path,Backup,Protocol,Name:string;
    Profile,I,J,N,Match,Offset,Count,MaxUID,Flags:Integer;
    IPv4:in_addr; IPv6:in6_addr;
    Apply,Found:Boolean;
    Config,Before,After:TBytes;
    Request:TStringList;
    LogField:TField;
begin
    Command:=LowerCase(ParamStr(1));
    if Command='set-server' then begin
        if (ParamCount<>4) and ((ParamCount<>5) or (ParamStr(5)<>'--apply')) then raise Exception.Create('Use set-server ROOT PROTOCOL REQUEST [--apply].');
        Apply:=ParamCount=5; Protocol:=ParamStr(3); RequestPath:=ParamStr(4);
    end else if Command='disable-servers' then begin
        if (ParamCount<>2) and ((ParamCount<>3) or (ParamStr(3)<>'--apply')) then raise Exception.Create('Use disable-servers ROOT [--apply].');
        Apply:=ParamCount=3; RequestPath:='';
    end else begin
        if (ParamCount<>3) and ((ParamCount<>4) or (ParamStr(4)<>'--apply')) then raise Exception.Create('Use command ROOT REQUEST [--apply].');
        Apply:=ParamCount=4; RequestPath:=ParamStr(3);
    end;
    Root:=PhysicalRoot(ParamStr(2)); Profile:=IdentifyProfile(Root);
    QualifyWriterBinary(Root,Profiles[Profile].Name); Config:=ReadConfig(Root,Profile);
    Request:=nil;
    try
        if RequestPath<>'' then Request:=LoadRequest(RequestPath);
        if Command='set-config' then begin
            Path:=IncludeTrailingPathDelimiter(Root)+'mystic.dat'; Before:=Config; After:=Copy(Before);
            for I:=0 to Request.Count-1 do begin
                Key:=Request.Names[I]; Value:=Request.ValueFromIndex[I]; Found:=False;
                if SameText(Key,'Python2Library') then Key:='Python2Lib';
                if SameText(Key,'Python3Library') then Key:='Python3Lib';
                for J:=0 to Profiles[Profile].FieldCount-1 do
                    if SameText(Key,Profiles[Profile].Fields[J].Name) then begin
                        PutString(After,Profiles[Profile].Fields[J].Offset,Profiles[Profile].Fields[J].Maximum,Value); Found:=True;
                    end;
                // A49 RecLogRoller facts from the qualified vendor records.
                if (Profiles[Profile].Name='1.12 A49') and not Found then begin
                    if FindLogDateField(Profile, Key, LogField) then begin
                        PutString(After, LogField.Offset, LogField.Maximum, Value);
                        Found := True;
                    end
                    else if FindCodePageField(Profile, Key, Offset) then begin
                        // Validate the existing byte before replacing it.
                        CodePageName(Key, After[Offset]);
                        After[Offset] := CodePageValue(Key, Value);
                        Found := True;
                    end
                    else if SameText(Key,'MISLogLevel') then begin PutNumber(After,4573,1,3,Value); if After[4573]=0 then raise Exception.Create('Log level cannot be zero.'); Found:=True; end
                    else if SameText(Key,'MISLogRollType') then begin PutNumber(After,4574,1,2,Value); Found:=True; end
                    else if FindLogFilesField(Profile, Key, LogField) then begin
                        PutNumber(After, LogField.Offset, LogField.Maximum, 65535, Value);
                        Found := True;
                    end
                    else if SameText(Key,'MISLogSize') then begin PutNumber(After,4577,4,High(LongWord),Value); Found:=True; end
                    else if SameText(Key,'MISLogCached') then begin PutNumber(After,4581,1,1,Value,True); Found:=True; end;
                end;
                if not Found then raise Exception.Create('Unqualified public configuration field.');
            end;
        end else begin
            Value:=GetString(Config,98,80);
            {$ifdef Windows}
            if ExtractFileDrive(Value)='' then
            {$else}
            if (Value='') or (Value[1]<>'/') then
            {$endif}
                raise Exception.Create('Native data directory must be absolute.');
            Path:=IncludeTrailingPathDelimiter(PhysicalRoot(Value));
            if Command='ban-event' then Path:=Path+'event.dat' else Path:=Path+'servers.dat';
            Before:=ReadRaw(Path); After:=Copy(Before);
            if Command='ban-event' then begin
                if Length(Before) mod 640<>0 then raise Exception.Create('Unknown event record size.');
                Match:=-1; MaxUID:=0;
                for N:=0 to Length(Before) div 640-1 do begin
                    Offset:=N*640; Count:=Read32(Before,Offset); if Count>MaxUID then MaxUID:=Count;
                    Name:=GetString(Before,Offset+6,40);
                    if SameText(Name,'Firewall Ban PowerShell') then begin
                        if Match>=0 then raise Exception.Create('Duplicate managed firewall event.'); Match:=Offset;
                    end else if (Before[Offset+4]<>0) and (Before[Offset+47]=5) then
                        raise Exception.Create('Another active IP Blocked event requires explicit migration.');
                end;
                if Match<0 then begin
                    if MaxUID=High(LongInt) then raise Exception.Create('Event UID space exhausted.');
                    Match:=Length(After); SetLength(After,Length(After)+640);
                    FillChar(After[Match],640,0); PutNumber(After,Match,4,High(LongInt),IntToStr(MaxUID+1));
                end;
                PutString(After,Match+6,40,'Firewall Ban PowerShell'); After[Match+47]:=5;
                if (Request.IndexOfName('Active')<0) or (Request.IndexOfName('Shell')<0) or (Request.Count<>2) then
                    raise Exception.Create('Firewall event request needs exactly Active and Shell.');
                PutNumber(After,Match+4,1,1,Request.Values['Active'],True);
                PutString(After,Match+57,160,Request.Values['Shell']);
                Flags:=Read32(After,Match+552) and not 1;
                PutNumber(After,Match+552,4,High(LongWord),UIntToStr(LongWord(Flags)));
            end else begin
                if Length(Before) mod 384<>0 then raise Exception.Create('Unknown server record size.');
                Match:=-1;
                for N:=0 to Length(Before) div 384-1 do begin
                    Offset:=N*384;
                    if Command='disable-servers' then After[Offset]:=0
                    else if SameText(GetString(Before,Offset+66,8),Protocol) then begin
                        if Match>=0 then raise Exception.Create('Ambiguous native server protocol.'); Match:=Offset;
                    end;
                end;
                if Command<>'disable-servers' then begin
                    if Match<0 then raise Exception.Create('Native server protocol not found.');
                    for I:=0 to Request.Count-1 do begin
                        Key:=Request.Names[I]; Value:=Request.ValueFromIndex[I];
                        // Relative offsets within the 384-byte ServerInfoRecord.
                        if SameText(Key,'IPv4Adapter') then begin
                            if (Value<>'') and not TryStrToHostAddr(Value,IPv4) then raise Exception.Create('Invalid IPv4 adapter.');
                            PutString(After,Match+1,19,Value);
                        end
                        else if SameText(Key,'IPv6Adapter') then begin
                            if (Value<>'') and not TryStrToHostAddr6(Value,IPv6) then raise Exception.Create('Invalid IPv6 adapter.');
                            PutString(After,Match+21,39,Value);
                        end
                        else if SameText(Key,'WebRoot') then PutString(After,Match+96,80,Value)
                        else if SameText(Key,'Active') then PutNumber(After,Match,1,1,Value,True)
                        else if SameText(Key,'AdapterType') then PutNumber(After,Match+61,1,2,Value)
                        else if SameText(Key,'Port') then begin PutNumber(After,Match+75,2,65535,Value); if Value='0' then raise Exception.Create('Port cannot be zero.'); end
                        else if SameText(Key,'MaxAllowed') then PutNumber(After,Match+77,2,65535,Value)
                        else if SameText(Key,'MaxIPs') then PutNumber(After,Match+79,1,255,Value)
                        else if SameText(Key,'BanIP') then PutNumber(After,Match+80,1,255,Value)
                        else if SameText(Key,'BanSecs') then PutNumber(After,Match+81,2,65535,Value)
                        else if SameText(Key,'TimeOut') then PutNumber(After,Match+83,2,65535,Value)
                        else if SameText(Key,'CountryBlock') then PutNumber(After,Match+85,1,1,Value,True)
                        else if SameText(Key,'SendBlocked') then PutNumber(After,Match+86,1,1,Value,True)
                        else if SameText(Key,'SSLPort') then PutNumber(After,Match+178,2,65535,Value)
                        else raise Exception.Create('Unqualified native server field.');
                    end;
                end;
            end;
        end;
        if SHA256Bytes(Before)=SHA256Bytes(After) then begin Writeln('Action=Unchanged'); Exit; end;
        if not Apply then begin Writeln('Action=Plan'); Writeln('Operation=',Command); Writeln('RequiresStopped=true'); Exit; end;
        Backup:=CommitData(Root,Path,Before,After);
        Writeln('Action=Applied'); Writeln('Operation=',Command); Writeln('Backup=',Backup);
        Writeln('ConfigSHA256=',SHA256Bytes(After));
    finally Request.Free; end;
end;

// DataPath (RecConfig offset 98, String[80]) locates the data files. It must
// be absolute, so a relative stored path cannot depend on the current directory.
function DataFile(const Config: TBytes; const Name: string): string;
var
    Value: string;
begin
    Value := GetString(Config, 98, 80);
    {$ifdef Windows}
    if ExtractFileDrive(Value) = '' then
    {$else}
    if (Value = '') or (Value[1] <> '/') then
    {$endif}
        raise Exception.Create('Native data directory must be absolute.');
    Result := IncludeTrailingPathDelimiter(PhysicalRoot(Value)) + Name;
end;

procedure ArchiveCommand;
var
    Command, Root, Extension, Path, Backup: string;
    Profile, Offset: Integer;
    OSType: Byte;
    Apply: Boolean;
    Config, Before, After: TBytes;
    Request: TStringList;
begin
    Command := LowerCase(ParamStr(1));
    Apply := False;
    if Command = 'get-archive' then
    begin
        if ParamCount <> 4 then
            raise Exception.Create('Use get-archive ROOT EXT OSTYPE.');
    end
    else
    begin
        if (ParamCount <> 5) and ((ParamCount <> 6) or (ParamStr(6) <> '--apply')) then
            raise Exception.Create('Use set-archive ROOT EXT OSTYPE REQUEST [--apply].');
        Apply := ParamCount = 6;
    end;
    Extension := NormalizeArchiveExtension(ParamStr(3));
    OSType := ArchiveOSTypeValue(ParamStr(4));

    Root := PhysicalRoot(ParamStr(2));
    Profile := IdentifyProfile(Root);
    // RecArchive is measured for the A49 records only.
    if Profiles[Profile].Name <> '1.12 A49' then
        raise Exception.Create('Archive records are qualified for A49 only.');
    if Command = 'set-archive' then
        QualifyWriterBinary(Root, Profiles[Profile].Name);
    Config := ReadConfig(Root, Profile);
    Path := DataFile(Config, 'archive.dat');
    Before := ReadRaw(Path);

    if Command = 'get-archive' then
    begin
        Offset := FindArchiveRecord(Before, Extension, OSType);
        if Offset < 0 then
            Writeln('Found=false')
        else
            WriteArchiveRecord(Before, Offset);
        Exit;
    end;

    Request := LoadRequest(ParamStr(5));
    try
        After := Copy(Before);
        ApplyArchiveRequest(After, Extension, OSType, Request);
    finally
        Request.Free;
    end;
    if SHA256Bytes(Before) = SHA256Bytes(After) then
    begin
        Writeln('Action=Unchanged');
        Exit;
    end;
    if not Apply then
    begin
        Writeln('Action=Plan');
        Writeln('Operation=', Command);
        if Length(After) <> Length(Before) then
            Writeln('Record=New')
        else
            Writeln('Record=Existing');
        Writeln('RequiresStopped=true');
        Exit;
    end;
    Backup := CommitData(Root, Path, Before, After);
    Writeln('Action=Applied');
    Writeln('Operation=', Command);
    Writeln('Backup=', Backup);
    Writeln('ArchiveSHA256=', SHA256Bytes(After));
end;


// Compares a request value with a stored field. Strings compare their
// payload only, so bytes behind the length do not matter.
function LeafMatches(const Data: TBytes; Base: Integer; const Leaf: TLeaf; const Value: string): Boolean;
var
    Scratch: TBytes;
    I, Count: Integer;
begin
    Scratch := Copy(Data, Base, Leaf.Offset + Leaf.Size);
    WriteLeaf(Scratch, 0, Leaf, Value);
    Count := Leaf.Size;
    if Leaf.Kind = lkString then
        Count := Scratch[Leaf.Offset] + 1;
    for I := 0 to Count - 1 do
        if Scratch[Leaf.Offset + I] <> Data[Base + Leaf.Offset + I] then
            Exit(False);
    Result := True;
end;

function RequireLeaf(RecordType: TRecordType; const Name: string): TLeaf;
begin
    if not FindLeaf(RecordType, Name, Result) then
        raise Exception.Create('Unknown field ' + Name + ' in ' + RecordType.Name + '.');
    if Result.Kind = lkPointer then
        raise Exception.Create(Name + ' is not stored in the file.');
end;

procedure RecordCommand;
var
    Command, Root, Path, Backup, Value: string;
    Profile, Count, I, J, Base, Match, Matches: Integer;
    Apply, Create: Boolean;
    Catalog: TRecordCatalog;
    RecordType: TRecordType;
    Item: TDataFile;
    Config, Before, After: TBytes;
    Leaf: TLeaf;
    Selected: TStringList;
    MatchFields, Fields, Options: TStringList;
    Highest, Current: Int64;
begin
    Command := LowerCase(ParamStr(1));
    Apply := False;
    if Command = 'set-record' then
    begin
        if (ParamCount <> 4) and ((ParamCount <> 5) or (ParamStr(5) <> '--apply')) then
            raise Exception.Create('Use set-record ROOT FILE REQUEST [--apply].');
        Apply := ParamCount = 5;
    end
    else if (Command = 'schema') and (ParamCount <> 3) then
        raise Exception.Create('Use schema ROOT FILE.')
    else if (Command = 'list') and (ParamCount < 3) then
        raise Exception.Create('Use list ROOT FILE [FIELD ...].');

    Root := PhysicalRoot(ParamStr(2));
    Profile := IdentifyProfile(Root);
    if Command = 'set-record' then
        QualifyWriterBinary(Root, Profiles[Profile].Name);
    Config := ReadConfig(Root, Profile);
    Catalog := LoadCatalog(Root);
    Selected := TStringList.Create;
    MatchFields := TStringList.Create;
    Fields := TStringList.Create;
    Options := TStringList.Create;
    try
        RecordType := ResolveRecordFile(Root, ParamStr(3), Catalog, Config, Item, Path);

        if Command = 'schema' then
        begin
            Writeln('File=', Item.FileName);
            Writeln('Type=', Item.TypeName);
            Writeln('RecordBytes=', RecordType.Size);
            for I := 0 to High(RecordType.Leaves) do
            begin
                Leaf := RecordType.Leaves[I];
                Value := IntToStr(Leaf.Offset) + ',' + IntToStr(Leaf.Size) + ',' + LeafKindName(Leaf.Kind);
                if Leaf.Kind = lkString then
                    Value := Value + ',' + IntToStr(Leaf.Maximum);
                if Leaf.Kind = lkSet then
                    Value := Value + ',' + IntToStr(Leaf.SetLow) + '-' + IntToStr(Leaf.SetHigh);
                if IsSecretLeaf(Leaf) then
                    Value := Value + ',secret';
                Writeln('Field.', Leaf.Name, '=', Value);
            end;
            Exit;
        end;

        if Item.InRoot then
            Before := Config
        else
            Before := ReadRaw(Path);
        if (Length(Before) mod RecordType.Size <> 0) or (Item.Single and (Length(Before) <> RecordType.Size)) then
            raise Exception.Create(Item.FileName + ' size does not match ' + Item.TypeName + '.');
        Count := Length(Before) div RecordType.Size;

        if Command = 'list' then
        begin
            for I := 4 to ParamCount do
            begin
                Leaf := RequireLeaf(RecordType, ParamStr(I));
                if IsSecretLeaf(Leaf) then
                    raise Exception.Create(Leaf.Name + ' is a credential and is never printed.');
                Selected.Add(Leaf.Name);
            end;
            Writeln('File=', Item.FileName);
            Writeln('Records=', Count);
            for J := 0 to Count - 1 do
            begin
                Base := J * RecordType.Size;
                for I := 0 to High(RecordType.Leaves) do
                begin
                    Leaf := RecordType.Leaves[I];
                    if Selected.Count > 0 then
                    begin
                        if Selected.IndexOf(Leaf.Name) < 0 then
                            Continue;
                    end
                    else if IsSecretLeaf(Leaf) or IsReservedLeaf(Leaf) or (Leaf.Kind = lkPointer) then
                        Continue;
                    Writeln(J, '.', Leaf.Name, '=', ReadLeaf(Before, Base, Leaf));
                end;
            end;
            Exit;
        end;

        // set-record
        LoadRecordRequest(ParamStr(4), MatchFields, Fields, Options);
        for I := 0 to Options.Count - 1 do
            if not SameText(Options.Names[I], 'Create') and not SameText(Options.Names[I], 'UniqueField') then
                raise Exception.Create('Options are Create and UniqueField.');
        Create := SameText(Options.Values['Create'], 'true');
        if (Options.Values['Create'] <> '') and not Create and not SameText(Options.Values['Create'], 'false') then
            raise Exception.Create('Create is true or false.');
        if Item.Single and ((MatchFields.Count > 0) or Create) then
            raise Exception.Create(Item.FileName + ' holds one record; use only Fields.');
        if not Item.Single and (MatchFields.Count = 0) then
            raise Exception.Create('A Match section selects the record to change.');

        Match := -1;
        Matches := 0;
        if Item.Single then
        begin
            Match := 0;
            Matches := 1;
        end
        else
            for J := 0 to Count - 1 do
            begin
                Base := J * RecordType.Size;
                I := 0;
                while I < MatchFields.Count do
                begin
                    Leaf := RequireLeaf(RecordType, MatchFields.Names[I]);
                    if not LeafMatches(Before, Base, Leaf, MatchFields.ValueFromIndex[I]) then
                        Break;
                    Inc(I);
                end;
                if I = MatchFields.Count then
                begin
                    Match := J;
                    Inc(Matches);
                end;
            end;
        if Matches > 1 then
            raise Exception.Create('Match selects ' + IntToStr(Matches) + ' records; add fields to select one.');
        if (Matches = 0) and not Create then
            raise Exception.Create('No record matches; set Create=true to append one.');

        After := Copy(Before);
        if Matches = 0 then
        begin
            // A new record starts zeroed, then takes the Match values.
            Match := Count;
            SetLength(After, Length(After) + RecordType.Size);
            FillChar(After[Match * RecordType.Size], RecordType.Size, 0);
            for I := 0 to MatchFields.Count - 1 do
                WriteLeaf(After, Match * RecordType.Size, RequireLeaf(RecordType, MatchFields.Names[I]),
                    MatchFields.ValueFromIndex[I]);
            if Options.Values['UniqueField'] <> '' then
            begin
                // Records such as RecEvent carry an ID that must stay unique.
                Leaf := RequireLeaf(RecordType, Options.Values['UniqueField']);
                if not (Leaf.Kind in [lkSigned, lkUnsigned]) then
                    raise Exception.Create('UniqueField must be numeric.');
                Highest := 0;
                for J := 0 to Count - 1 do
                begin
                    Current := StrToInt64(ReadLeaf(Before, J * RecordType.Size, Leaf));
                    if Current > Highest then
                        Highest := Current;
                end;
                WriteLeaf(After, Match * RecordType.Size, Leaf, IntToStr(Highest + 1));
            end;
        end;
        Base := Match * RecordType.Size;
        for I := 0 to Fields.Count - 1 do
        begin
            Leaf := RequireLeaf(RecordType, Fields.Names[I]);
            if (Options.Values['UniqueField'] <> '') and SameText(Leaf.Name, Options.Values['UniqueField']) then
                raise Exception.Create('UniqueField is assigned by mdatmod.');
            WriteLeaf(After, Base, Leaf, Fields.ValueFromIndex[I]);
        end;

        if SHA256Bytes(Before) = SHA256Bytes(After) then
        begin
            Writeln('Action=Unchanged');
            Writeln('Record=', Match);
            Exit;
        end;
        if not Apply then
        begin
            Writeln('Action=Plan');
            Writeln('Operation=set-record');
            if Matches = 0 then
                Writeln('Record=New')
            else
                Writeln('Record=', Match);
            Writeln('RequiresStopped=true');
            Exit;
        end;
        Backup := CommitRecords(Root, Path, Before, After, RecordType.Size);
        Writeln('Action=Applied');
        Writeln('Operation=set-record');
        Writeln('Record=', Match);
        Writeln('Backup=', Backup);
        Writeln('DataSHA256=', SHA256Bytes(After));
    finally
        Options.Free;
        Fields.Free;
        MatchFields.Free;
        Selected.Free;
        Catalog.Free;
    end;
end;

procedure Run;
var
    Command, Root: string;
    Profile, I: Integer;
    Data: TBytes;
    LogField: TField;
begin
    if (ParamCount = 0) or SameText(ParamStr(1), '--help') or
        SameText(ParamStr(1), '-h') or SameText(ParamStr(1), '/h') or
        (ParamStr(1) = '/?') then
    begin
        Usage;
        Exit;
    end;
    Command := LowerCase(ParamStr(1));
    if (Command = '--self-test') and (ParamCount = 1) then
    begin
        SelfTest;
        Exit;
    end;
    if (Command = '--hash') and (ParamCount = 2) then
    begin
        Writeln(SHA256File(ParamStr(2)));
        Exit;
    end;
    if Command='check-offline' then begin
        if ParamCount<>2 then raise Exception.Create('Use check-offline ROOT.');
        Root:=PhysicalRoot(ParamStr(2)); Profile:=IdentifyProfile(Root);
        QualifyWriterBinary(Root,Profiles[Profile].Name); RequireStopped(Root);
        Writeln('State=Stopped'); Exit;
    end;
    if Command='profile' then begin
        if ParamCount<>2 then raise Exception.Create('Use profile ROOT.');
        Root:=PhysicalRoot(ParamStr(2)); Profile:=IdentifyProfile(Root);
        QualifyWriterBinary(Root,Profiles[Profile].Name);
        Writeln('Profile=',Profiles[Profile].Name);
        Writeln('RecordsSHA256=',Profiles[Profile].DocsHash);
        Writeln('RecordBytes=',Profiles[Profile].ConfigSize); Exit;
    end;
    if (Command='set-config') or (Command='set-server') or (Command='disable-servers') or (Command='ban-event') then begin
        BatchCommand; Exit;
    end;
    if (Command = 'schema') or (Command = 'list') or (Command = 'set-record') then
    begin
        RecordCommand;
        Exit;
    end;
    if (Command = 'get-archive') or (Command = 'set-archive') then
    begin
        ArchiveCommand;
        Exit;
    end;
    if (Command='set') or (Command='restore') then begin
        WriteCommand; Exit;
    end;
    if ((Command = 'inspect') and (ParamCount = 2)) or
        ((Command = 'get') and (ParamCount = 3)) then
    begin
        Root := ExpandFileName(ParamStr(2));
        Profile := IdentifyProfile(Root);
        Data := ReadConfig(Root, Profile);
        if Command = 'inspect' then
        begin
            Writeln('Profile=', Profiles[Profile].Name);
            Writeln('DataVersion=', Profiles[Profile].DataVersion);
            Writeln('RecordBytes=', Length(Data));
            Writeln('RecordsSHA256=', Profiles[Profile].DocsHash);
            Writeln('ConfigSHA256=', SHA256Bytes(Data));
            Writeln('WritesEnabled=false');
            Exit;
        end;
        for I := 0 to Profiles[Profile].FieldCount - 1 do
            if SameText(Profiles[Profile].Fields[I].Name, ParamStr(3)) then
            begin
                Writeln(SafeString(Data, Profiles[Profile].Fields[I]));
                Exit;
            end;
        if FindLogDateField(Profile, ParamStr(3), LogField) then
        begin
            Writeln(SafeString(Data, LogField));
            Exit;
        end;
        if FindCodePageField(Profile, ParamStr(3), I) then
        begin
            Writeln(CodePageName(ParamStr(3), Data[I]));
            Exit;
        end;
        if FindLogFilesField(Profile, ParamStr(3), LogField) then
        begin
            Writeln(Word(Data[LogField.Offset]) or (Word(Data[LogField.Offset + 1]) shl 8));
            Exit;
        end;
        raise Exception.Create('Field is not in the public configuration allowlist.');
    end;
    raise Exception.Create('Unsupported command. Use --help.');
end;

begin
    try
        Run;
    except
        on E: Exception do
        begin
            Writeln(StdErr, 'mdatmod: ', E.Message);
            Halt(2);
        end;
    end;
end.
