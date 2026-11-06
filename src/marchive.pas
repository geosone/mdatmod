unit marchive;
{$mode objfpc}{$H+}

// A49 ARCHIVE.DAT editing. RecArchive in the hashed vendor records.112 is a
// packed record of 281 bytes; tools/writerlayoutprobe.pas checks every
// zero-based offset and total reservation below against the vendor source:
//
//   offset  size  field   storage
//        0     1  OSType  Byte (0 Windows, 1 Linux, 2 macOS, 3 all systems)
//        1     1  Active  Boolean (0 or 1)
//        2    31  Desc    String[30]: length byte plus 30 payload bytes
//       33     5  Ext     String[4]:  length byte plus 4 payload bytes
//       38    81  Pack    String[80]: length byte plus 80 payload bytes
//      119    81  Unpack  String[80]
//      200    81  View    String[80]
//
// OSType 4 is OS/2 and is not offered. A record is selected by the pair of
// extension and OSType, as Mystic itself keeps one record per pair.

interface

uses Classes, SysUtils;

const
    ArchiveRecordSize = 281;

function ArchiveOSTypeValue(const Name: string): Byte;
function ArchiveOSTypeName(Value: Byte): string;
function NormalizeArchiveExtension(const Value: string): string;
function FindArchiveRecord(const Data: TBytes; const Extension: string; OSType: Byte): Integer;
procedure WriteArchiveRecord(const Data: TBytes; Offset: Integer);
procedure ApplyArchiveRequest(var Data: TBytes; const Extension: string; OSType: Byte; Request: TStringList);

implementation

uses mrequest;

const
    OSTypeOffset = 0;
    ActiveOffset = 1;
    DescOffset = 2;
    DescMaximum = 30;
    ExtOffset = 33;
    ExtMaximum = 4;
    PackOffset = 38;
    UnpackOffset = 119;
    ViewOffset = 200;
    CommandMaximum = 80;

function ArchiveOSTypeValue(const Name: string): Byte;
begin
    if SameText(Name, 'Windows') then
        Exit(0);
    if SameText(Name, 'Linux') then
        Exit(1);
    if SameText(Name, 'macOS') then
        Exit(2);
    if SameText(Name, 'All') then
        Exit(3);
    raise Exception.Create('Use OSType Windows, Linux, macOS or All.');
end;

function ArchiveOSTypeName(Value: Byte): string;
begin
    case Value of
        0: Result := 'Windows';
        1: Result := 'Linux';
        2: Result := 'macOS';
        3: Result := 'All';
    else
        raise Exception.Create('Unknown native archive OSType value.');
    end;
end;

function NormalizeArchiveExtension(const Value: string): string;
var
    I: Integer;
begin
    // Mystic stores extensions upper case without a dot; only letters and
    // digits are accepted so that a request cannot store wildcards or paths.
    Result := UpperCase(Value);
    if (Length(Result) < 1) or (Length(Result) > ExtMaximum) then
        raise Exception.Create('Archive extensions have one to four characters.');
    for I := 1 to Length(Result) do
    begin
        if not (Result[I] in ['A'..'Z', '0'..'9']) then
            raise Exception.Create('Archive extensions accept letters and digits only.');
    end;
end;

procedure CheckArchiveLayout(const Data: TBytes);
begin
    if Length(Data) mod ArchiveRecordSize <> 0 then
        raise Exception.Create('Unknown archive record size.');
end;

function FindArchiveRecord(const Data: TBytes; const Extension: string; OSType: Byte): Integer;
var
    Index, Offset: Integer;
begin
    CheckArchiveLayout(Data);
    Result := -1;
    for Index := 0 to Length(Data) div ArchiveRecordSize - 1 do
    begin
        Offset := Index * ArchiveRecordSize;
        if (Data[Offset + OSTypeOffset] = OSType) and
            SameText(GetString(Data, Offset + ExtOffset, ExtMaximum), Extension) then
        begin
            if Result >= 0 then
                raise Exception.Create('Ambiguous native archive record.');
            Result := Offset;
        end;
    end;
end;

function Printable(const Data: TBytes; Offset, Maximum: Integer): string;
var
    Raw: string;
    I: Integer;
begin
    // Escape bytes outside printable ASCII; no stored code page is guessed.
    Raw := GetString(Data, Offset, Maximum);
    Result := '';
    for I := 1 to Length(Raw) do
    begin
        if (Ord(Raw[I]) >= 32) and (Ord(Raw[I]) <= 126) then
            Result := Result + Raw[I]
        else
            Result := Result + '\x' + IntToHex(Ord(Raw[I]), 2);
    end;
end;

procedure WriteArchiveRecord(const Data: TBytes; Offset: Integer);
begin
    Writeln('Found=true');
    Writeln('Record=', Offset div ArchiveRecordSize + 1);
    Writeln('OSType=', ArchiveOSTypeName(Data[Offset + OSTypeOffset]));
    Writeln('Extension=', Printable(Data, Offset + ExtOffset, ExtMaximum));
    Writeln('Active=', LowerCase(BoolToStr(Data[Offset + ActiveOffset] <> 0, True)));
    Writeln('Description=', Printable(Data, Offset + DescOffset, DescMaximum));
    Writeln('Pack=', Printable(Data, Offset + PackOffset, CommandMaximum));
    Writeln('Unpack=', Printable(Data, Offset + UnpackOffset, CommandMaximum));
    Writeln('View=', Printable(Data, Offset + ViewOffset, CommandMaximum));
end;

procedure ApplyArchiveRequest(var Data: TBytes; const Extension: string; OSType: Byte; Request: TStringList);
var
    Offset, I: Integer;
    Key, Value: string;
begin
    Offset := FindArchiveRecord(Data, Extension, OSType);
    if Offset < 0 then
    begin
        // A new record needs at least a state and a name that the sysop can
        // recognise in the native editor. It is appended; existing record
        // numbers stay unchanged.
        if (Request.IndexOfName('Active') < 0) or (Request.IndexOfName('Description') < 0) then
            raise Exception.Create('A new archive record needs Active and Description.');
        Offset := Length(Data);
        SetLength(Data, Length(Data) + ArchiveRecordSize);
        FillChar(Data[Offset], ArchiveRecordSize, 0);
        Data[Offset + OSTypeOffset] := OSType;
        PutString(Data, Offset + ExtOffset, ExtMaximum, Extension);
    end
    else if Data[Offset + ActiveOffset] > 1 then
        raise Exception.Create('Invalid native archive Active value.');

    for I := 0 to Request.Count - 1 do
    begin
        Key := Request.Names[I];
        Value := Request.ValueFromIndex[I];
        if SameText(Key, 'Active') then
            PutNumber(Data, Offset + ActiveOffset, 1, 1, Value, True)
        else if SameText(Key, 'Description') then
            PutString(Data, Offset + DescOffset, DescMaximum, Value)
        else if SameText(Key, 'Pack') then
            PutString(Data, Offset + PackOffset, CommandMaximum, Value)
        else if SameText(Key, 'Unpack') then
            PutString(Data, Offset + UnpackOffset, CommandMaximum, Value)
        else if SameText(Key, 'View') then
            PutString(Data, Offset + ViewOffset, CommandMaximum, Value)
        else
            raise Exception.Create('Unqualified native archive field.');
    end;
end;

end.
