program mdatmod;

{$mode objfpc}{$H+}

uses Classes, SysUtils, Sockets, msha256, mprofiles, msafeio, mrequest;

procedure Usage;
begin
    Writeln('mdatmod 0.3.0 - qualified offline Mystic DAT tool');
    Writeln('  mdatmod inspect ROOT');
    Writeln('  mdatmod get ROOT FIELD');
    Writeln('  mdatmod set ROOT FIELD VALUE [--apply]');
    Writeln('  mdatmod restore ROOT BACKUP [--apply]');
    Writeln('  mdatmod profile ROOT');
    Writeln('  mdatmod set-config ROOT REQUEST.ini [--apply]');
    Writeln('  mdatmod set-server ROOT PROTOCOL REQUEST.ini [--apply]');
    Writeln('  mdatmod disable-servers ROOT [--apply]');
    Writeln('  mdatmod ban-event ROOT REQUEST.ini [--apply]');
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

function ReadRaw(const Path:string):TBytes;
var Stream:TFileStream;
begin
    Result:=nil;
    Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyNone);
    try
        if Stream.Size>1048576 then raise Exception.Create('Backup exceeds the supported record size.');
        SetLength(Result,Stream.Size);
        if Length(Result)>0 then Stream.ReadBuffer(Result[0],Length(Result));
    finally Stream.Free; end;
end;

procedure WriteCommand;
var Root,FieldName,Value,Backup,Checksum,Command,TargetPath,Relative:string;
    Profile,Index,I:Integer;
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
        end else raise Exception.Create('Unsupported backup target.');
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
                    if SameText(Key,'MISLogDateFormat') then begin PutString(After,4582,25,Value); Found:=True; end
                    else if SameText(Key,'MISLogLevel') then begin PutNumber(After,4573,1,3,Value); if After[4573]=0 then raise Exception.Create('Log level cannot be zero.'); Found:=True; end
                    else if SameText(Key,'MISLogRollType') then begin PutNumber(After,4574,1,2,Value); Found:=True; end
                    else if SameText(Key,'MISLogFiles') then begin PutNumber(After,4575,2,65535,Value); Found:=True; end
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

procedure Run;
var
    Command, Root: string;
    Profile, I: Integer;
    Data: TBytes;
begin
    if (ParamCount = 0) or (ParamStr(1) = '--help') then
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
