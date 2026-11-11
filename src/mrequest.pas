unit mrequest;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils;
function LoadRequest(const Path:string):TStringList;
procedure LoadRecordRequest(const Path:string; Match, Fields, Options:TStringList);
procedure PutString(var Data:TBytes; Offset,Maximum:Integer; const Value:string);
function GetString(const Data:TBytes; Offset,Maximum:Integer):string;
procedure PutNumber(var Data:TBytes; Offset,Width:Integer; Maximum:QWord; const Value:string; BooleanField:Boolean=False);
function Read32(const Data:TBytes; Offset:Integer):LongInt;
implementation
function LoadRequest(const Path:string):TStringList;
var Lines:TStringList; I,P:Integer; Text,Key,Value:string; Section:Boolean;
begin
    Result:=TStringList.Create; Result.CaseSensitive:=False;
    Lines:=TStringList.Create; Section:=False;
    try
        Lines.LoadFromFile(Path);
        if Length(Lines.Text)>65536 then raise Exception.Create('Request is too large.');
        for I:=0 to Lines.Count-1 do begin
            Text:=Trim(Lines[I]);
            if (Text='') or (Text[1]=';') or (Text[1]='#') then Continue;
            if SameText(Text,'[Fields]') then begin
                if Section then raise Exception.Create('Duplicate request section.');
                Section:=True; Continue;
            end;
            P:=Pos('=',Text);
            if not Section or (P<2) then raise Exception.Create('Expected one Fields section with key=value entries.');
            Key:=Trim(Copy(Text,1,P-1)); Value:=Trim(Copy(Text,P+1,MaxInt));
            if Result.IndexOfName(Key)>=0 then raise Exception.Create('Duplicate request field.');
            Result.Add(Key+'='+Value);
        end;
        if (not Section) or (Result.Count=0) then raise Exception.Create('Request has no fields.');
    except Result.Free; Lines.Free; raise; end;
    Lines.Free;
end;
// set-record requests: [Match] selects the record by field values, [Fields]
// holds the new values and [Options] the switches Create and UniqueField.
// Each section may appear once; keys are field names as schema prints them.
procedure LoadRecordRequest(const Path:string; Match, Fields, Options:TStringList);
var
    Lines: TStringList;
    Target: TStringList;
    Seen: TStringList;
    I, P: Integer;
    Text, Key, Value: string;
begin
    Lines := TStringList.Create;
    Seen := TStringList.Create;
    Target := nil;
    try
        Lines.LoadFromFile(Path);
        if Length(Lines.Text) > 65536 then
            raise Exception.Create('Request is too large.');
        for I := 0 to Lines.Count - 1 do
        begin
            Text := Trim(Lines[I]);
            if (Text = '') or (Text[1] = ';') or (Text[1] = '#') then
                Continue;
            if (Text[1] = '[') and (Text[Length(Text)] = ']') then
            begin
                Key := LowerCase(Copy(Text, 2, Length(Text) - 2));
                if Seen.IndexOf(Key) >= 0 then
                    raise Exception.Create('Duplicate request section.');
                Seen.Add(Key);
                if Key = 'match' then
                    Target := Match
                else if Key = 'fields' then
                    Target := Fields
                else if Key = 'options' then
                    Target := Options
                else
                    raise Exception.Create('Use the sections Match, Fields and Options.');
                Continue;
            end;
            P := Pos('=', Text);
            if (Target = nil) or (P < 2) then
                raise Exception.Create('Expected key=value entries inside a section.');
            Key := Trim(Copy(Text, 1, P - 1));
            Value := Trim(Copy(Text, P + 1, MaxInt));
            if Target.IndexOfName(Key) >= 0 then
                raise Exception.Create('Duplicate request key ' + Key + '.');
            Target.Add(Key + '=' + Value);
        end;
        if Fields.Count = 0 then
            raise Exception.Create('Request has no Fields section entries.');
    finally
        Seen.Free;
        Lines.Free;
    end;
end;

procedure PutString(var Data:TBytes; Offset,Maximum:Integer; const Value:string);
var I:Integer;
begin
    if (Offset<0) or (Offset+Maximum>=Length(Data)) then
        raise Exception.Create('String field lies outside the qualified native record.');
    if Length(Value)>Maximum then
        raise Exception.Create('Value exceeds the native Pascal string capacity.');
    for I:=1 to Length(Value) do if (Ord(Value[I])<32) or (Ord(Value[I])>126) then
        raise Exception.Create('Current writes accept printable ASCII only.');
    FillChar(Data[Offset],Maximum+1,0); Data[Offset]:=Length(Value);
    for I:=1 to Length(Value) do Data[Offset+I]:=Ord(Value[I]);
end;
function GetString(const Data:TBytes; Offset,Maximum:Integer):string;
var I,Count:Integer;
begin
    if (Offset<0) or (Offset+Maximum>=Length(Data)) then raise Exception.Create('String lies outside the qualified record.');
    Count:=Data[Offset];
    if Count>Maximum then raise Exception.Create('Invalid native string length.');
    Result:='';
    for I:=1 to Count do Result:=Result+Chr(Data[Offset+I]);
end;
procedure PutNumber(var Data:TBytes; Offset,Width:Integer; Maximum:QWord; const Value:string; BooleanField:Boolean);
var Number:QWord; I:Integer;
begin
    if BooleanField then begin
        if SameText(Value,'true') then Number:=1
        else if SameText(Value,'false') then Number:=0
        else raise Exception.Create('Boolean fields require true or false.');
    end else if not TryStrToQWord(Value,Number) then raise Exception.Create('Invalid unsigned numeric field.');
    if (Number>Maximum) or (Offset<0) or (Offset+Width>Length(Data)) then
        raise Exception.Create('Numeric field is outside its native storage range.');
    for I:=0 to Width-1 do Data[Offset+I]:=(Number shr (I*8)) and $ff;
end;
function Read32(const Data:TBytes; Offset:Integer):LongInt;
begin
    if (Offset<0) or (Offset+4>Length(Data)) then raise Exception.Create('Integer lies outside the record.');
    Result:=LongInt(LongWord(Data[Offset]) or (LongWord(Data[Offset+1]) shl 8) or
        (LongWord(Data[Offset+2]) shl 16) or (LongWord(Data[Offset+3]) shl 24));
end;
end.
