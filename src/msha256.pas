unit msha256;

{$mode objfpc}{$H+}{$Q-}{$R-}

interface

uses Classes, SysUtils;

function SHA256Bytes(const Data: TBytes): string;
function SHA256File(const FileName: string): string;

implementation

type
    TBlock = array[0..63] of Byte;
    TState = array[0..7] of Cardinal;

const
    K: array[0..63] of Cardinal = (
        $428a2f98, $71374491, $b5c0fbcf, $e9b5dba5, $3956c25b, $59f111f1, $923f82a4, $ab1c5ed5,
        $d807aa98, $12835b01, $243185be, $550c7dc3, $72be5d74, $80deb1fe, $9bdc06a7, $c19bf174,
        $e49b69c1, $efbe4786, $0fc19dc6, $240ca1cc, $2de92c6f, $4a7484aa, $5cb0a9dc, $76f988da,
        $983e5152, $a831c66d, $b00327c8, $bf597fc7, $c6e00bf3, $d5a79147, $06ca6351, $14292967,
        $27b70a85, $2e1b2138, $4d2c6dfc, $53380d13, $650a7354, $766a0abb, $81c2c92e, $92722c85,
        $a2bfe8a1, $a81a664b, $c24b8b70, $c76c51a3, $d192e819, $d6990624, $f40e3585, $106aa070,
        $19a4c116, $1e376c08, $2748774c, $34b0bcb5, $391c0cb3, $4ed8aa4a, $5b9cca4f, $682e6ff3,
        $748f82ee, $78a5636f, $84c87814, $8cc70208, $90befffa, $a4506ceb, $bef9a3f7, $c67178f2
    );

function RotateRight(Value: Cardinal; Bits: Byte): Cardinal; inline;
begin
    Result := (Value shr Bits) or (Value shl (32 - Bits));
end;

procedure Compress(var State: TState; const Block: TBlock);
var
    W: array[0..63] of Cardinal;
    A, B, C, D, E, F, G, H, S0, S1, T1, T2: Cardinal;
    I: Integer;
begin
    for I := 0 to 15 do
        W[I] := (Cardinal(Block[I * 4]) shl 24) or
            (Cardinal(Block[I * 4 + 1]) shl 16) or
            (Cardinal(Block[I * 4 + 2]) shl 8) or Block[I * 4 + 3];
    for I := 16 to 63 do
    begin
        S0 := RotateRight(W[I - 15], 7) xor RotateRight(W[I - 15], 18) xor (W[I - 15] shr 3);
        S1 := RotateRight(W[I - 2], 17) xor RotateRight(W[I - 2], 19) xor (W[I - 2] shr 10);
        W[I] := W[I - 16] + S0 + W[I - 7] + S1;
    end;
    A := State[0];
    B := State[1];
    C := State[2];
    D := State[3];
    E := State[4];
    F := State[5];
    G := State[6];
    H := State[7];
    for I := 0 to 63 do
    begin
        S1 := RotateRight(E, 6) xor RotateRight(E, 11) xor RotateRight(E, 25);
        T1 := H + S1 + ((E and F) xor ((not E) and G)) + K[I] + W[I];
        S0 := RotateRight(A, 2) xor RotateRight(A, 13) xor RotateRight(A, 22);
        T2 := S0 + ((A and B) xor (A and C) xor (B and C));
        H := G;
        G := F;
        F := E;
        E := D + T1;
        D := C;
        C := B;
        B := A;
        A := T1 + T2;
    end;
    State[0] := State[0] + A;
    State[1] := State[1] + B;
    State[2] := State[2] + C;
    State[3] := State[3] + D;
    State[4] := State[4] + E;
    State[5] := State[5] + F;
    State[6] := State[6] + G;
    State[7] := State[7] + H;
end;

function SHA256Bytes(const Data: TBytes): string;
var
    State: TState;
    Block: TBlock;
    Position, Remaining, I: SizeInt;
    BitLength: QWord;
begin
    State[0] := $6a09e667;
    State[1] := $bb67ae85;
    State[2] := $3c6ef372;
    State[3] := $a54ff53a;
    State[4] := $510e527f;
    State[5] := $9b05688c;
    State[6] := $1f83d9ab;
    State[7] := $5be0cd19;
    Position := 0;
    while Length(Data) - Position >= 64 do
    begin
        Move(Data[Position], Block[0], 64);
        Compress(State, Block);
        Inc(Position, 64);
    end;
    FillChar(Block, SizeOf(Block), 0);
    Remaining := Length(Data) - Position;
    if Remaining > 0 then
        Move(Data[Position], Block[0], Remaining);
    Block[Remaining] := $80;
    if Remaining >= 56 then
    begin
        Compress(State, Block);
        FillChar(Block, SizeOf(Block), 0);
    end;
    BitLength := QWord(Length(Data)) * 8;
    for I := 0 to 7 do
        Block[63 - I] := Byte(BitLength shr (I * 8));
    Compress(State, Block);
    Result := '';
    for I := 0 to 7 do
        Result := Result + LowerCase(IntToHex(State[I], 8));
end;

function SHA256File(const FileName: string): string;
var
    Stream: TFileStream;
    Data: TBytes;
begin
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
        if Stream.Size > 64 * 1024 * 1024 then
            raise Exception.Create('Profile input exceeds the 64 MiB limit.');
        SetLength(Data, Stream.Size);
        if Length(Data) > 0 then
            Stream.ReadBuffer(Data[0], Length(Data));
    finally
        Stream.Free;
    end;
    Result := SHA256Bytes(Data);
end;

end.
