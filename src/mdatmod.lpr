program mdatmod;

{$mode objfpc}{$H+}

uses Classes, SysUtils, msha256, mprofiles;

procedure Usage;
begin
    Writeln('mdatmod 0.1 - Mystic DAT profile inspection (read-only research build)');
    Writeln('  mdatmod inspect ROOT');
    Writeln('  mdatmod get ROOT FIELD');
    Writeln('  mdatmod --hash FILE');
    Writeln('  mdatmod --self-test');
    Writeln('No DAT writes are implemented in this build.');
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
    raise Exception.Create('Unsupported command. This research build cannot modify DAT files.');
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
