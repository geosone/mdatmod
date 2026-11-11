unit mrecords;
{$mode objfpc}{$H+}

// Generic Mystic DAT record layouts, read at run time from the vendor
// records.112 that each installation ships in docs/. The caller identifies
// that file by its SHA-256 first (mprofiles), so only a known vendor source
// is parsed; no vendor record text is embedded in mdatmod.
//
// records.112 declares {$PACKRECORDS 1}: fields follow each other without
// padding. Sizes follow Free Pascal, the compiler Mystic is built with:
//   Byte, ShortInt, Boolean, Char        1 byte
//   Word, SmallInt (Integer is SmallInt) 2 bytes, little endian
//   LongInt, Cardinal, LongWord          4 bytes, little endian
//   Int64, UInt64, QWord                 8 bytes, little endian
//   String[N]                            one length byte plus N payload bytes
//   Set of L..H                          4 bytes when H < 32, otherwise 32;
//                                        member M is bit M mod 8 of byte M div 8
//   ^Type, AnsiString                    one pointer; never stored in a file
// tests/test_schema.py compiles a probe of every computed field offset with
// Free Pascal against the same records.112 and compares the results.

interface

uses Classes, SysUtils;

type
    TLeafKind = (lkUnsigned, lkSigned, lkBoolean, lkChar, lkString, lkSet, lkPointer);

    // One storable value inside a record. Offset is zero-based from the start
    // of the outermost record; Size is the total reservation in bytes.
    // Maximum is the payload capacity of a String[N]; SetLow and SetHigh are
    // the bounds of a set's base range.
    TLeaf = record
        Name: string;
        Offset: Integer;
        Size: Integer;
        Kind: TLeafKind;
        Maximum: Integer;
        SetLow: Integer;
        SetHigh: Integer;
    end;
    TLeafArray = array of TLeaf;

    TRecordType = class
    public
        Name: string;
        Size: Integer;
        Leaves: TLeafArray;
        // False when the type holds pointers or managed strings, which a DAT
        // file cannot contain.
        Storable: Boolean;
        function Clone: TRecordType;
    end;

    TRecordCatalog = class
    private
        FTypes: TStringList;
        FConstants: TStringList;
        FPointerSize: Integer;
    public
        constructor Create(PointerSize: Integer);
        destructor Destroy; override;
        procedure LoadFromFile(const Path: string; const Defines: array of string);
        procedure AddType(const Name: string; RecordType: TRecordType);
        function Find(const Name: string): TRecordType;
        function FindConstant(const Name: string; out Value: Int64): Boolean;
        procedure AddConstant(const Name: string; Value: Int64);
        property PointerSize: Integer read FPointerSize;
    end;

    // A DAT file and the record type it holds.
    TDataFile = record
        FileName: string;
        TypeName: string;
        InRoot: Boolean;
        Single: Boolean;
        Personal: Boolean;
    end;

function FindDataFile(const FileName: string; out Item: TDataFile): Boolean;
function IsSecretLeaf(const Leaf: TLeaf): Boolean;
function IsReservedLeaf(const Leaf: TLeaf): Boolean;
function FindLeaf(RecordType: TRecordType; const Name: string; out Leaf: TLeaf): Boolean;
function ReadLeaf(const Data: TBytes; Base: Integer; const Leaf: TLeaf): string;
procedure WriteLeaf(var Data: TBytes; Base: Integer; const Leaf: TLeaf; const Value: string);
function LeafKindName(Kind: TLeafKind): string;

implementation

const
    // Mystic 1.12 data files and their records.112 types. Files live in
    // DataPath unless InRoot is set. users.dat and callers.dat hold personal
    // data and are refused for reading and writing.
    DataFiles: array[0..15] of TDataFile = (
        (FileName: 'mystic.dat'; TypeName: 'RecConfig'; InRoot: True; Single: True; Personal: False),
        (FileName: 'archive.dat'; TypeName: 'RecArchive'; InRoot: False; Single: False; Personal: False),
        (FileName: 'event.dat'; TypeName: 'RecEvent'; InRoot: False; Single: False; Personal: False),
        (FileName: 'security.dat'; TypeName: 'RecSecurity'; InRoot: False; Single: False; Personal: False),
        (FileName: 'mbases.dat'; TypeName: 'RecMessageBase'; InRoot: False; Single: False; Personal: False),
        (FileName: 'fbases.dat'; TypeName: 'RecFileBase'; InRoot: False; Single: False; Personal: False),
        (FileName: 'groups_g.dat'; TypeName: 'RecGroup'; InRoot: False; Single: False; Personal: False),
        (FileName: 'groups_f.dat'; TypeName: 'RecGroup'; InRoot: False; Single: False; Personal: False),
        (FileName: 'protocol.dat'; TypeName: 'RecProtocol'; InRoot: False; Single: False; Personal: False),
        (FileName: 'servers.dat'; TypeName: 'ServerInfoRecord'; InRoot: False; Single: False; Personal: False),
        (FileName: 'echonode.dat'; TypeName: 'RecEchoMailNode'; InRoot: False; Single: False; Personal: False),
        (FileName: 'echogroup.dat'; TypeName: 'RecEchoMailGroup'; InRoot: False; Single: False; Personal: False),
        (FileName: 'qwknet.dat'; TypeName: 'RecQwkNetwork'; InRoot: False; Single: False; Personal: False),
        (FileName: 'history.dat'; TypeName: 'RecHistory'; InRoot: False; Single: False; Personal: False),
        (FileName: 'users.dat'; TypeName: 'RecUser'; InRoot: False; Single: False; Personal: True),
        (FileName: 'callers.dat'; TypeName: 'RecLastOn'; InRoot: False; Single: False; Personal: True)
    );

type
    TTokenKind = (tkEnd, tkIdentifier, tkNumber, tkString, tkSymbol);

    TToken = record
        Kind: TTokenKind;
        Text: string;
        Line: Integer;
    end;

    TParser = class
    private
        FTokens: array of TToken;
        FPosition: Integer;
        FCatalog: TRecordCatalog;
        function Peek(Ahead: Integer = 0): TToken;
        function Next: TToken;
        function IsWord(const Token: TToken; const Text: string): Boolean;
        procedure Expect(const Text: string);
        function ExpectIdentifier: string;
        procedure Fail(const Message: string);
        function ParseExpression: Int64;
        function ParseTerm: Int64;
        function ParseFactor: Int64;
        function ParseType: TRecordType;
        function ParseRecord: TRecordType;
        function ParseArray: TRecordType;
        function ParseSet: TRecordType;
        function ParseSubrange(Low: Int64): TRecordType;
        procedure ParseConstSection;
        procedure ParseTypeSection;
        procedure SkipToSemicolon;
    public
        constructor Create(Catalog: TRecordCatalog);
        procedure Tokenize(const Text: string);
        procedure Run;
    end;

{ Type construction }

function NewScalar(const Name: string; Size: Integer; Kind: TLeafKind): TRecordType;
begin
    Result := TRecordType.Create;
    Result.Name := Name;
    Result.Size := Size;
    Result.Storable := Kind <> lkPointer;
    SetLength(Result.Leaves, 1);
    Result.Leaves[0].Name := '';
    Result.Leaves[0].Offset := 0;
    Result.Leaves[0].Size := Size;
    Result.Leaves[0].Kind := Kind;
    Result.Leaves[0].Maximum := 0;
    Result.Leaves[0].SetLow := 0;
    Result.Leaves[0].SetHigh := 0;
end;

function TRecordType.Clone: TRecordType;
begin
    Result := TRecordType.Create;
    Result.Name := Name;
    Result.Size := Size;
    Result.Storable := Storable;
    Result.Leaves := Copy(Leaves);
end;

// Appends the leaves of Part, named below Prefix and shifted by Offset.
// An element prefix such as "[3]" joins without a dot.
procedure AppendLeaves(Target, Part: TRecordType; const Prefix: string; Offset: Integer);
var
    I, Start: Integer;
    Leaf: TLeaf;
begin
    Start := Length(Target.Leaves);
    SetLength(Target.Leaves, Start + Length(Part.Leaves));
    for I := 0 to High(Part.Leaves) do
    begin
        Leaf := Part.Leaves[I];
        if Leaf.Name = '' then
            Leaf.Name := Prefix
        else if (Prefix <> '') and (Leaf.Name[1] = '[') then
            Leaf.Name := Prefix + Leaf.Name
        else if Prefix <> '' then
            Leaf.Name := Prefix + '.' + Leaf.Name;
        Leaf.Offset := Leaf.Offset + Offset;
        Target.Leaves[Start + I] := Leaf;
    end;
end;

{ TRecordCatalog }

constructor TRecordCatalog.Create(PointerSize: Integer);
begin
    inherited Create;
    FPointerSize := PointerSize;
    FTypes := TStringList.Create;
    FTypes.CaseSensitive := False;
    FTypes.OwnsObjects := True;
    FConstants := TStringList.Create;
    FConstants.CaseSensitive := False;
    AddType('Byte', NewScalar('Byte', 1, lkUnsigned));
    AddType('ShortInt', NewScalar('ShortInt', 1, lkSigned));
    AddType('Boolean', NewScalar('Boolean', 1, lkBoolean));
    AddType('Char', NewScalar('Char', 1, lkChar));
    AddType('AnsiChar', NewScalar('AnsiChar', 1, lkChar));
    AddType('Word', NewScalar('Word', 2, lkUnsigned));
    AddType('SmallInt', NewScalar('SmallInt', 2, lkSigned));
    AddType('LongInt', NewScalar('LongInt', 4, lkSigned));
    AddType('Cardinal', NewScalar('Cardinal', 4, lkUnsigned));
    AddType('LongWord', NewScalar('LongWord', 4, lkUnsigned));
    AddType('DWord', NewScalar('DWord', 4, lkUnsigned));
    AddType('Int64', NewScalar('Int64', 8, lkSigned));
    AddType('UInt64', NewScalar('UInt64', 8, lkUnsigned));
    AddType('QWord', NewScalar('QWord', 8, lkUnsigned));
    AddType('System.Word', NewScalar('System.Word', 2, lkUnsigned));
    AddType('AnsiString', NewScalar('AnsiString', FPointerSize, lkPointer));
    AddType('Pointer', NewScalar('Pointer', FPointerSize, lkPointer));
end;

destructor TRecordCatalog.Destroy;
begin
    FTypes.Free;
    FConstants.Free;
    inherited Destroy;
end;

procedure TRecordCatalog.AddType(const Name: string; RecordType: TRecordType);
var
    Index: Integer;
begin
    RecordType.Name := Name;
    // A later declaration (Integer = SmallInt) replaces the predefined one.
    Index := FTypes.IndexOf(Name);
    if Index >= 0 then
        FTypes.Delete(Index);
    FTypes.AddObject(Name, RecordType);
end;

function TRecordCatalog.Find(const Name: string): TRecordType;
var
    Index: Integer;
begin
    Index := FTypes.IndexOf(Name);
    if Index < 0 then
        Exit(nil);
    Result := TRecordType(FTypes.Objects[Index]);
end;

procedure TRecordCatalog.AddConstant(const Name: string; Value: Int64);
begin
    FConstants.Values[Name] := IntToStr(Value);
end;

function TRecordCatalog.FindConstant(const Name: string; out Value: Int64): Boolean;
var
    Index: Integer;
begin
    Value := 0;
    Index := FConstants.IndexOfName(Name);
    if Index < 0 then
        Exit(False);
    Value := StrToInt64(FConstants.ValueFromIndex[Index]);
    Result := True;
end;

// Removes comments and resolves {$IFDEF}/{$IFNDEF}/{$ELSE}/{$ENDIF} against
// Defines. {$PACKRECORDS} must be 1; other directives are dropped. Line breaks
// survive so parser messages report the source line.
function Preprocess(const Text: string; const Defines: array of string): string;
var
    I, J, K: Integer;
    Directive, Word, Argument: string;
    Active: array of Boolean;
    Output: TStringBuilder;

    function Defined(const Name: string): Boolean;
    var
        D: Integer;
    begin
        for D := 0 to High(Defines) do
            if SameText(Defines[D], Name) then
                Exit(True);
        Result := False;
    end;

    function Emitting: Boolean;
    var
        D: Integer;
    begin
        for D := 0 to High(Active) do
            if not Active[D] then
                Exit(False);
        Result := True;
    end;

    procedure KeepLineBreaks(First, Last: Integer);
    var
        P: Integer;
    begin
        for P := First to Last do
            if Text[P] = #10 then
                Output.Append(#10);
    end;

begin
    Output := TStringBuilder.Create;
    SetLength(Active, 0);
    try
        I := 1;
        while I <= Length(Text) do
        begin
            if (Text[I] = '/') and (I < Length(Text)) and (Text[I + 1] = '/') then
            begin
                while (I <= Length(Text)) and (Text[I] <> #10) do
                    Inc(I);
                Continue;
            end;
            if (Text[I] = '(') and (I < Length(Text)) and (Text[I + 1] = '*') then
            begin
                J := Pos('*)', Copy(Text, I + 2, MaxInt));
                if J = 0 then
                    raise Exception.Create('Unterminated comment in records.112.');
                K := I + J + 2;
                KeepLineBreaks(I, K);
                I := K + 1;
                Continue;
            end;
            if Text[I] = '{' then
            begin
                J := Pos('}', Copy(Text, I + 1, MaxInt));
                if J = 0 then
                    raise Exception.Create('Unterminated brace comment in records.112.');
                Directive := Copy(Text, I + 1, J - 1);
                K := I + J;
                KeepLineBreaks(I, K);
                I := K + 1;
                if (Directive = '') or (Directive[1] <> '$') then
                    Continue;
                Directive := Trim(Copy(Directive, 2, MaxInt));
                Word := UpperCase(Directive);
                Argument := '';
                if Pos(' ', Word) > 0 then
                begin
                    Argument := Trim(Copy(Directive, Pos(' ', Word) + 1, MaxInt));
                    Word := Copy(Word, 1, Pos(' ', Word) - 1);
                end;
                if (Word = 'IFDEF') or (Word = 'IFNDEF') then
                begin
                    SetLength(Active, Length(Active) + 1);
                    Active[High(Active)] := Defined(Argument) = (Word = 'IFDEF');
                end
                else if Word = 'ELSE' then
                begin
                    if Length(Active) = 0 then
                        raise Exception.Create('Unbalanced $ELSE in records.112.');
                    Active[High(Active)] := not Active[High(Active)];
                end
                else if Word = 'ENDIF' then
                begin
                    if Length(Active) = 0 then
                        raise Exception.Create('Unbalanced $ENDIF in records.112.');
                    SetLength(Active, Length(Active) - 1);
                end
                else if (Word = 'PACKRECORDS') and Emitting and (Argument <> '1') then
                    raise Exception.Create('Only {$PACKRECORDS 1} layouts are supported.')
                else if (Word = 'I') and Emitting then
                    // {$I %DATE%} only appears inside string constants.
                    Output.Append(''' ''');
                Continue;
            end;
            if Emitting then
                Output.Append(Text[I])
            else if Text[I] = #10 then
                Output.Append(#10);
            Inc(I);
        end;
        if Length(Active) <> 0 then
            raise Exception.Create('Unterminated $IFDEF in records.112.');
        Result := Output.ToString;
    finally
        Output.Free;
    end;
end;

procedure TRecordCatalog.LoadFromFile(const Path: string; const Defines: array of string);
var
    Source: TStringList;
    Parser: TParser;
begin
    Source := TStringList.Create;
    Parser := TParser.Create(Self);
    try
        Source.LoadFromFile(Path);
        if Length(Source.Text) > 1048576 then
            raise Exception.Create('records.112 is unexpectedly large.');
        Parser.Tokenize(Preprocess(Source.Text, Defines));
        Parser.Run;
    finally
        Parser.Free;
        Source.Free;
    end;
end;

{ TParser }

constructor TParser.Create(Catalog: TRecordCatalog);
begin
    inherited Create;
    FCatalog := Catalog;
    FPosition := 0;
end;

procedure TParser.Tokenize(const Text: string);
var
    I, Start, Line, Count: Integer;

    procedure Add(Kind: TTokenKind; const Value: string);
    begin
        if Count = Length(FTokens) then
            SetLength(FTokens, Count * 2 + 256);
        FTokens[Count].Kind := Kind;
        FTokens[Count].Text := Value;
        FTokens[Count].Line := Line;
        Inc(Count);
    end;

begin
    SetLength(FTokens, 0);
    Count := 0;
    Line := 1;
    I := 1;
    while I <= Length(Text) do
    begin
        case Text[I] of
            #10:
                begin
                    Inc(Line);
                    Inc(I);
                end;
            #0..#9, #11..' ':
                Inc(I);
            'A'..'Z', 'a'..'z', '_':
                begin
                    Start := I;
                    while (I <= Length(Text)) and (Text[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
                        Inc(I);
                    Add(tkIdentifier, Copy(Text, Start, I - Start));
                end;
            '0'..'9', '$':
                begin
                    Start := I;
                    Inc(I);
                    while (I <= Length(Text)) and (Text[I] in ['0'..'9', 'A'..'F', 'a'..'f']) do
                        Inc(I);
                    Add(tkNumber, Copy(Text, Start, I - Start));
                end;
            '''':
                begin
                    Start := I;
                    Inc(I);
                    while (I <= Length(Text)) and (Text[I] <> '''') do
                        Inc(I);
                    Inc(I);
                    Add(tkString, Copy(Text, Start, I - Start));
                end;
            '#':
                begin
                    // Character constants such as #13#10.
                    Start := I;
                    Inc(I);
                    while (I <= Length(Text)) and (Text[I] in ['0'..'9', '$', 'A'..'F', 'a'..'f']) do
                        Inc(I);
                    Add(tkString, Copy(Text, Start, I - Start));
                end;
            '.':
                if (I < Length(Text)) and (Text[I + 1] = '.') then
                begin
                    Add(tkSymbol, '..');
                    Inc(I, 2);
                end
                else
                begin
                    Add(tkSymbol, '.');
                    Inc(I);
                end;
        else
            begin
                Add(tkSymbol, Text[I]);
                Inc(I);
            end;
        end;
    end;
    Add(tkEnd, '');
    SetLength(FTokens, Count);
end;

function TParser.Peek(Ahead: Integer): TToken;
begin
    if FPosition + Ahead > High(FTokens) then
        Exit(FTokens[High(FTokens)]);
    Result := FTokens[FPosition + Ahead];
end;

function TParser.Next: TToken;
begin
    Result := Peek;
    if FPosition < High(FTokens) then
        Inc(FPosition);
end;

function TParser.IsWord(const Token: TToken; const Text: string): Boolean;
begin
    Result := (Token.Kind in [tkIdentifier, tkSymbol]) and SameText(Token.Text, Text);
end;

procedure TParser.Fail(const Message: string);
begin
    raise Exception.CreateFmt('records.112 line %d: %s', [Peek.Line, Message]);
end;

procedure TParser.Expect(const Text: string);
begin
    if not IsWord(Peek, Text) then
        Fail('expected ' + Text + ', found ' + Peek.Text);
    Next;
end;

function TParser.ExpectIdentifier: string;
begin
    if Peek.Kind <> tkIdentifier then
        Fail('expected an identifier, found ' + Peek.Text);
    Result := Next.Text;
end;

procedure TParser.SkipToSemicolon;
begin
    while (Peek.Kind <> tkEnd) and not IsWord(Peek, ';') do
        Next;
    Next;
end;

// Integer constant expressions: literals, $hex, known constants, + - * div,
// unary minus and parentheses. A string operand raises, and the caller skips
// that constant.
function TParser.ParseExpression: Int64;
begin
    Result := ParseTerm;
    while IsWord(Peek, '+') or IsWord(Peek, '-') do
    begin
        if Next.Text = '+' then
            Result := Result + ParseTerm
        else
            Result := Result - ParseTerm;
    end;
end;

function TParser.ParseTerm: Int64;
begin
    Result := ParseFactor;
    while IsWord(Peek, '*') or IsWord(Peek, 'div') do
    begin
        if Next.Text = '*' then
            Result := Result * ParseFactor
        else
            Result := Result div ParseFactor;
    end;
end;

function TParser.ParseFactor: Int64;
var
    Token: TToken;
begin
    Result := 0;
    Token := Next;
    if IsWord(Token, '-') then
        Exit(-ParseFactor);
    if IsWord(Token, '(') then
    begin
        Result := ParseExpression;
        Expect(')');
        Exit;
    end;
    if (Token.Kind = tkNumber) and TryStrToInt64(Token.Text, Result) then
        Exit;
    if (Token.Kind = tkIdentifier) and FCatalog.FindConstant(Token.Text, Result) then
        Exit;
    raise Exception.Create('not an integer constant');
end;

procedure TParser.ParseConstSection;
var
    Name: string;
    Start: Integer;
    Value: Int64;
begin
    while (Peek.Kind = tkIdentifier) and (IsWord(Peek(1), '=') or IsWord(Peek(1), ':')) do
    begin
        Name := Next.Text;
        if IsWord(Next, ':') then
        begin
            // Typed constants are never array bounds.
            SkipToSemicolon;
            Continue;
        end;
        Start := FPosition;
        try
            Value := ParseExpression;
            if not IsWord(Peek, ';') then
                raise Exception.Create('not an integer constant');
            Next;
            FCatalog.AddConstant(Name, Value);
        except
            on Exception do
            begin
                FPosition := Start;
                SkipToSemicolon;
            end;
        end;
    end;
end;

procedure TParser.ParseTypeSection;
var
    Name: string;
    RecordType: TRecordType;
begin
    while (Peek.Kind = tkIdentifier) and IsWord(Peek(1), '=') do
    begin
        Name := Next.Text;
        Next;
        RecordType := ParseType;
        try
            Expect(';');
        except
            RecordType.Free;
            raise;
        end;
        FCatalog.AddType(Name, RecordType);
    end;
end;

// Integer subrange L..H stored in the smallest fitting integer.
function TParser.ParseSubrange(Low: Int64): TRecordType;
var
    High: Int64;
begin
    Expect('..');
    High := ParseExpression;
    if Low >= 0 then
    begin
        if High <= 255 then
            Exit(NewScalar('', 1, lkUnsigned));
        if High <= 65535 then
            Exit(NewScalar('', 2, lkUnsigned));
        if High <= 4294967295 then
            Exit(NewScalar('', 4, lkUnsigned));
        Exit(NewScalar('', 8, lkUnsigned));
    end;
    if (Low >= -128) and (High <= 127) then
        Exit(NewScalar('', 1, lkSigned));
    if (Low >= -32768) and (High <= 32767) then
        Exit(NewScalar('', 2, lkSigned));
    if (Low >= -2147483648) and (High <= 2147483647) then
        Exit(NewScalar('', 4, lkSigned));
    Result := NewScalar('', 8, lkSigned);
end;

// Returns a new type object owned by the caller.
function TParser.ParseType: TRecordType;
var
    Name: string;
    Found: TRecordType;
    Value: Int64;
    Size: Int64;
begin
    if IsWord(Peek, 'Packed') then
        Next;
    if IsWord(Peek, 'Record') then
        Exit(ParseRecord);
    if IsWord(Peek, 'Array') then
        Exit(ParseArray);
    if IsWord(Peek, 'Set') then
        Exit(ParseSet);
    if IsWord(Peek, '^') then
    begin
        Next;
        ExpectIdentifier;
        Exit(NewScalar('', FCatalog.PointerSize, lkPointer));
    end;
    if IsWord(Peek, 'String') then
    begin
        Next;
        if not IsWord(Peek, '[') then
            // A plain String is a managed string here, never a file field.
            Exit(NewScalar('', FCatalog.PointerSize, lkPointer));
        Next;
        Size := ParseExpression;
        Expect(']');
        if (Size < 1) or (Size > 255) then
            Fail('invalid short-string capacity');
        Result := NewScalar('', Size + 1, lkString);
        Result.Leaves[0].Maximum := Size;
        Exit;
    end;
    if IsWord(Peek, '(') then
        Fail('enumerated types are not supported');
    if (Peek.Kind = tkNumber) or IsWord(Peek, '-') then
        Exit(ParseSubrange(ParseExpression));
    Name := ExpectIdentifier;
    if IsWord(Peek, '.') and (Peek(1).Kind = tkIdentifier) then
    begin
        Next;
        Name := Name + '.' + Next.Text;
    end;
    if FCatalog.FindConstant(Name, Value) and IsWord(Peek, '..') then
        Exit(ParseSubrange(Value));
    Found := FCatalog.Find(Name);
    if Found = nil then
        Fail('unknown type ' + Name);
    Result := Found.Clone;
end;

function TParser.ParseRecord: TRecordType;
var
    Names: TStringList;
    FieldType: TRecordType;
    I: Integer;
begin
    Expect('Record');
    Result := TRecordType.Create;
    Result.Size := 0;
    Result.Storable := True;
    Names := TStringList.Create;
    try
        try
            while not IsWord(Peek, 'End') do
            begin
                if IsWord(Peek, 'case') then
                    Fail('variant records are not supported');
                Names.Clear;
                Names.Add(ExpectIdentifier);
                while IsWord(Peek, ',') do
                begin
                    Next;
                    Names.Add(ExpectIdentifier);
                end;
                Expect(':');
                FieldType := ParseType;
                try
                    for I := 0 to Names.Count - 1 do
                    begin
                        AppendLeaves(Result, FieldType, Names[I], Result.Size);
                        Result.Size := Result.Size + FieldType.Size;
                    end;
                    Result.Storable := Result.Storable and FieldType.Storable;
                finally
                    FieldType.Free;
                end;
                if IsWord(Peek, ';') then
                    Next
                else if not IsWord(Peek, 'End') then
                    Fail('expected ; or End');
            end;
            Expect('End');
        except
            Result.Free;
            raise;
        end;
    finally
        Names.Free;
    end;
end;

function TParser.ParseArray: TRecordType;
var
    Lows, Highs: array of Int64;
    Element, Inner: TRecordType;
    Dimension: Integer;
    // A loop counter must be a native ordinal on 32-bit targets.
    Index: Integer;
begin
    Expect('Array');
    Expect('[');
    SetLength(Lows, 0);
    SetLength(Highs, 0);
    repeat
        SetLength(Lows, Length(Lows) + 1);
        SetLength(Highs, Length(Highs) + 1);
        Lows[High(Lows)] := ParseExpression;
        Expect('..');
        Highs[High(Highs)] := ParseExpression;
        if Highs[High(Highs)] < Lows[High(Lows)] then
            Fail('empty array range');
        if (Lows[High(Lows)] < -1000000) or (Highs[High(Highs)] > 1000000) then
            Fail('array range too large');
        if not IsWord(Peek, ',') then
            Break;
        Next;
    until False;
    Expect(']');
    Expect('of');
    Element := ParseType;
    // Array[A..B, C..D] of T is Array[A..B] of Array[C..D] of T.
    for Dimension := High(Lows) downto 0 do
    begin
        Inner := TRecordType.Create;
        Inner.Size := 0;
        Inner.Storable := Element.Storable;
        for Index := Integer(Lows[Dimension]) to Integer(Highs[Dimension]) do
        begin
            AppendLeaves(Inner, Element, '[' + IntToStr(Index) + ']', Inner.Size);
            Inner.Size := Inner.Size + Element.Size;
        end;
        Element.Free;
        Element := Inner;
    end;
    Result := Element;
end;

function TParser.ParseSet: TRecordType;
var
    Low, High: Int64;
    Name: string;
begin
    Expect('Set');
    Expect('of');
    if Peek.Kind = tkIdentifier then
    begin
        Name := Peek.Text;
        if SameText(Name, 'Char') or SameText(Name, 'Byte') then
        begin
            Next;
            Low := 0;
            High := 255;
        end
        else
        begin
            Low := ParseExpression;
            Expect('..');
            High := ParseExpression;
        end;
    end
    else
    begin
        Low := ParseExpression;
        Expect('..');
        High := ParseExpression;
    end;
    if (Low < 0) or (High > 255) or (High < Low) then
        Fail('unsupported set range');
    if High < 32 then
        Result := NewScalar('', 4, lkSet)
    else
        Result := NewScalar('', 32, lkSet);
    Result.Leaves[0].SetLow := Low;
    Result.Leaves[0].SetHigh := High;
end;

procedure TParser.Run;
begin
    while Peek.Kind <> tkEnd do
    begin
        if IsWord(Peek, 'Const') then
        begin
            Next;
            ParseConstSection;
        end
        else if IsWord(Peek, 'Type') then
        begin
            Next;
            ParseTypeSection;
        end
        else
            Fail('unexpected ' + Peek.Text);
    end;
end;

{ Data files and values }

function FindDataFile(const FileName: string; out Item: TDataFile): Boolean;
var
    I: Integer;
begin
    for I := Low(DataFiles) to High(DataFiles) do
        if SameText(DataFiles[I].FileName, FileName) then
        begin
            Item := DataFiles[I];
            Exit(True);
        end;
    Result := False;
end;

// The last path component without array indexes, e.g. "Password" for
// "Password[3]" or "Zone" for "NetAddress[1].Zone".
function BaseName(const Name: string): string;
var
    P: Integer;
begin
    Result := Name;
    P := LastDelimiter('.', Result);
    if P > 0 then
        Result := Copy(Result, P + 1, MaxInt);
    P := Pos('[', Result);
    if P > 0 then
        Result := Copy(Result, 1, P - 1);
end;

// Credentials are never printed: Password, CryptKey and any *Pass or *PW
// field (SysopPW, BinkPass, SMTPPass, ...). Writes stay possible through a
// request file, which keeps the value off the command line.
function IsSecretLeaf(const Leaf: TLeaf): Boolean;
var
    Name: string;
begin
    Name := LowerCase(BaseName(Leaf.Name));
    Result := (Name = 'password') or (Name = 'cryptkey') or
        ((Length(Name) > 4) and (Copy(Name, Length(Name) - 3, 4) = 'pass')) or
        ((Length(Name) > 2) and (Copy(Name, Length(Name) - 1, 2) = 'pw'));
end;

// Reserved padding, listed only when asked for by name.
function IsReservedLeaf(const Leaf: TLeaf): Boolean;
var
    Parts: TStringArray;
    Part: string;
    P: Integer;
begin
    Parts := Leaf.Name.Split(['.']);
    for Part in Parts do
    begin
        P := Pos('[', Part);
        if P > 0 then
        begin
            if SameText(Copy(Part, 1, P - 1), 'Res') or SameText(Copy(Part, 1, P - 1), 'Reserved') or
                SameText(Copy(Part, 1, P - 1), 'UNUSED') then
                Exit(True);
        end
        else if SameText(Part, 'Res') or SameText(Part, 'Reserved') or SameText(Part, 'UNUSED') then
            Exit(True);
    end;
    Result := False;
end;

function FindLeaf(RecordType: TRecordType; const Name: string; out Leaf: TLeaf): Boolean;
var
    I: Integer;
begin
    for I := 0 to High(RecordType.Leaves) do
        if SameText(RecordType.Leaves[I].Name, Name) then
        begin
            Leaf := RecordType.Leaves[I];
            Exit(True);
        end;
    Result := False;
end;

function LeafKindName(Kind: TLeafKind): string;
begin
    case Kind of
        lkUnsigned:
            Result := 'unsigned';
        lkSigned:
            Result := 'signed';
        lkBoolean:
            Result := 'boolean';
        lkChar:
            Result := 'char';
        lkString:
            Result := 'string';
        lkSet:
            Result := 'set';
    else
        Result := 'pointer';
    end;
end;

procedure CheckBounds(const Data: TBytes; Base: Integer; const Leaf: TLeaf);
begin
    if (Base < 0) or (Base + Leaf.Offset < 0) or (Base + Leaf.Offset + Leaf.Size > Length(Data)) then
        raise Exception.Create('Field lies outside the record.');
    if Leaf.Kind = lkPointer then
        raise Exception.Create('Pointer fields are not stored in DAT files.');
end;

function ReadUnsigned(const Data: TBytes; Offset, Size: Integer): QWord;
var
    I: Integer;
begin
    Result := 0;
    for I := Size - 1 downto 0 do
        Result := (Result shl 8) or Data[Offset + I];
end;

// Bytes 32..126 are written as they are. Every other byte, and a backslash
// that would read as the start of an escape, becomes \xNN. No code page is
// guessed.
function EscapeByte(const Data: TBytes; Offset, Last: Integer): string;
var
    Value: Byte;
begin
    Value := Data[Offset];
    if (Value < 32) or (Value > 126) then
        Exit('\x' + IntToHex(Value, 2));
    if (Value = Ord('\')) and (Offset < Last) and (Data[Offset + 1] = Ord('x')) then
        Exit('\x5C');
    Result := Chr(Value);
end;

function ReadLeaf(const Data: TBytes; Base: Integer; const Leaf: TLeaf): string;
var
    Offset, Count, I: Integer;
    Raw: QWord;
    Signed: Int64;
begin
    CheckBounds(Data, Base, Leaf);
    Offset := Base + Leaf.Offset;
    case Leaf.Kind of
        lkUnsigned:
            Result := IntToStr(ReadUnsigned(Data, Offset, Leaf.Size));
        lkSigned:
            begin
                Raw := ReadUnsigned(Data, Offset, Leaf.Size);
                if (Leaf.Size < 8) and (Raw and (QWord(1) shl (Leaf.Size * 8 - 1)) <> 0) then
                    Signed := Int64(Raw) - (Int64(1) shl (Leaf.Size * 8))
                else
                    Signed := Int64(Raw);
                Result := IntToStr(Signed);
            end;
        lkBoolean:
            case Data[Offset] of
                0:
                    Result := 'false';
                1:
                    Result := 'true';
            else
                Result := IntToStr(Data[Offset]);
            end;
        lkChar:
            Result := EscapeByte(Data, Offset, Offset);
        lkString:
            begin
                Count := Data[Offset];
                if Count > Leaf.Maximum then
                    raise Exception.Create('Invalid Pascal short-string length in ' + Leaf.Name + '.');
                Result := '';
                for I := 1 to Count do
                    Result := Result + EscapeByte(Data, Offset + I, Offset + Count);
            end;
        lkSet:
            begin
                Result := '';
                for I := Leaf.SetLow to Leaf.SetHigh do
                    if Data[Offset + I div 8] and (1 shl (I mod 8)) <> 0 then
                    begin
                        if Result <> '' then
                            Result := Result + ',';
                        Result := Result + IntToStr(I);
                    end;
            end;
    end;
end;

// Decodes printable ASCII with \xNN escapes into bytes.
function DecodeText(const Value: string): TBytes;
var
    I, Count, Code: Integer;
begin
    Result := nil;
    SetLength(Result, Length(Value));
    Count := 0;
    I := 1;
    while I <= Length(Value) do
    begin
        if (Value[I] = '\') and (I + 3 <= Length(Value)) and (Value[I + 1] = 'x') and
            TryStrToInt('$' + Copy(Value, I + 2, 2), Code) then
        begin
            Result[Count] := Code;
            Inc(I, 4);
        end
        else
        begin
            if (Ord(Value[I]) < 32) or (Ord(Value[I]) > 126) then
                raise Exception.Create('Values are printable ASCII; write other bytes as \xNN.');
            Result[Count] := Ord(Value[I]);
            Inc(I);
        end;
        Inc(Count);
    end;
    SetLength(Result, Count);
end;

procedure WriteUnsigned(var Data: TBytes; Offset, Size: Integer; Value: QWord);
var
    I: Integer;
begin
    for I := 0 to Size - 1 do
        Data[Offset + I] := (Value shr (I * 8)) and $FF;
end;

procedure WriteLeaf(var Data: TBytes; Base: Integer; const Leaf: TLeaf; const Value: string);
var
    Offset, I, Member: Integer;
    Unsigned: QWord;
    Signed: Int64;
    Bytes: TBytes;
    Members: TStringArray;
begin
    CheckBounds(Data, Base, Leaf);
    Offset := Base + Leaf.Offset;
    case Leaf.Kind of
        lkUnsigned:
            begin
                if not TryStrToQWord(Value, Unsigned) then
                    raise Exception.Create(Leaf.Name + ' needs an unsigned number.');
                if (Leaf.Size < 8) and (Unsigned >= QWord(1) shl (Leaf.Size * 8)) then
                    raise Exception.Create(Leaf.Name + ' is outside its native range.');
                WriteUnsigned(Data, Offset, Leaf.Size, Unsigned);
            end;
        lkSigned:
            begin
                if not TryStrToInt64(Value, Signed) then
                    raise Exception.Create(Leaf.Name + ' needs a number.');
                if (Leaf.Size < 8) and ((Signed < -(Int64(1) shl (Leaf.Size * 8 - 1))) or
                    (Signed >= Int64(1) shl (Leaf.Size * 8 - 1))) then
                    raise Exception.Create(Leaf.Name + ' is outside its native range.');
                WriteUnsigned(Data, Offset, Leaf.Size, QWord(Signed));
            end;
        lkBoolean:
            if SameText(Value, 'true') or (Value = '1') then
                Data[Offset] := 1
            else if SameText(Value, 'false') or (Value = '0') then
                Data[Offset] := 0
            else
                raise Exception.Create(Leaf.Name + ' needs true or false.');
        lkChar:
            begin
                Bytes := DecodeText(Value);
                if Length(Bytes) <> 1 then
                    raise Exception.Create(Leaf.Name + ' needs exactly one character.');
                Data[Offset] := Bytes[0];
            end;
        lkString:
            begin
                Bytes := DecodeText(Value);
                if Length(Bytes) > Leaf.Maximum then
                    raise Exception.Create(Leaf.Name + ' exceeds its native Pascal string capacity.');
                // Clear the whole reservation so no stale bytes remain.
                FillChar(Data[Offset], Leaf.Size, 0);
                Data[Offset] := Length(Bytes);
                for I := 0 to High(Bytes) do
                    Data[Offset + 1 + I] := Bytes[I];
            end;
        lkSet:
            begin
                FillChar(Data[Offset], Leaf.Size, 0);
                if Trim(Value) = '' then
                    Exit;
                Members := Value.Split([',']);
                for I := 0 to High(Members) do
                begin
                    if not TryStrToInt(Trim(Members[I]), Member) or (Member < Leaf.SetLow) or
                        (Member > Leaf.SetHigh) then
                        raise Exception.Create(Leaf.Name + ' holds members ' + IntToStr(Leaf.SetLow) +
                            '..' + IntToStr(Leaf.SetHigh) + ' only.');
                    Data[Offset + Member div 8] := Data[Offset + Member div 8] or (1 shl (Member mod 8));
                end;
            end;
    end;
end;

end.
