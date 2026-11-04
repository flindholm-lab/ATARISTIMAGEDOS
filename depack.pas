unit Depack;

{$F+,R-,S-,I-,V-,A-}

interface

uses Dos;

const
  MAX_SEG_BLOCKS = 16; { 16 * 32KB = 512KB max memory buffer }

type
  PBlock32K = ^TBlock32K;
  TBlock32K = array[0..32767] of Byte;

  TSegBuffer = record
    Blocks: array[0..MAX_SEG_BLOCKS - 1] of PBlock32K;
    NumBlocks: Integer;
    TotalSize: LongInt;
  end;

  { VLC record for Pack-Ice }
  TVLC = record
    BitLengths: array[0..7] of Integer;
    Offsets: array[0..7] of Integer;
    Count: Integer;
  end;

  { Huffman record for RNC }
  TRNCHufEntry = record
    Depth: Byte;
    Code: Word;
  end;
  TRNCHufTable = array[0..15] of TRNCHufEntry;

{ Memory Management }
procedure SegInit(var S: TSegBuffer);
function  SegAllocate(var S: TSegBuffer; Size: LongInt): Boolean;
procedure SegFree(var S: TSegBuffer);
procedure SegSetByte(var S: TSegBuffer; Offset: LongInt; Val: Byte);
function  SegGetByte(var S: TSegBuffer; Offset: LongInt): Byte;
function  SegReadWordBE(var S: TSegBuffer; Offset: LongInt): Word;
function  SegReadLongBE(var S: TSegBuffer; Offset: LongInt): LongInt;
function  SegCheckString(var S: TSegBuffer; Offset: LongInt; const Str: string): Boolean;
function  SegLoadFromFile(var S: TSegBuffer; const FileName: string): Boolean;
function  SegSaveToFile(var S: TSegBuffer; const FileName: string; Count: LongInt): Boolean;

{ Packer Signature Detection }
function DetectBufferPacker(var InBuf: TSegBuffer): string;

{ Individual Decompressors }
function DecompressPackIce(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
const
  IceDeltas: array[0..4] of Integer = (0, -2, 2, -4, 4);
function DecompressAtomik(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
function DecompressRNC(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
function DecompressPompey(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
function DecompressAutomation(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
function DecompressDegasPC(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
function DecompressDegasPC1(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
function DecompressTitusPC1(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
function DecompressFire(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
function DecompressPowerPacker(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
function DecompressThunder(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
function DecompressStosSquash(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
function Decompress4PAK(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
function DecompressSentry(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
function DecompressStad(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
function DecompressHappy(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
function DecompressJek(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
function DecompressJam(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;

{ Master Dispatcher }
function DepackUniversal(const InPath, OutPath: string; var PackerName: string; var DepackedSize: LongInt): Boolean;

implementation

{ =============================================================================
  Segmented Buffer (TSegBuffer) Implementation
  Handles up to 512KB in 16-bit Real Mode without 64KB segment overflow
  ============================================================================= }

procedure SegInit(var S: TSegBuffer);
var I: Integer;
begin
  S.NumBlocks := 0;
  S.TotalSize := 0;
  for I := 0 to MAX_SEG_BLOCKS - 1 do S.Blocks[I] := nil;
end;

function SegAllocate(var S: TSegBuffer; Size: LongInt): Boolean;
var
  Needed, I: Integer;
begin
  SegAllocate := False;
  SegInit(S);
  if Size <= 0 then Exit;
  Needed := (Size + 32767) div 32768;
  if Needed > MAX_SEG_BLOCKS then Exit;

  for I := 0 to Needed - 1 do
  begin
    if MaxAvail < 32768 then
    begin
      { Out of memory: free partially allocated blocks }
      while I > 0 do
      begin
        Dec(I);
        FreeMem(S.Blocks[I], 32768);
        S.Blocks[I] := nil;
      end;
      Exit;
    end;
    GetMem(S.Blocks[I], 32768);
    FillChar(S.Blocks[I]^, 32768, 0);
  end;
  S.NumBlocks := Needed;
  S.TotalSize := Size;
  SegAllocate := True;
end;

procedure SegFree(var S: TSegBuffer);
var I: Integer;
begin
  for I := 0 to S.NumBlocks - 1 do
  begin
    if S.Blocks[I] <> nil then
    begin
      FreeMem(S.Blocks[I], 32768);
      S.Blocks[I] := nil;
    end;
  end;
  S.NumBlocks := 0;
  S.TotalSize := 0;
end;

procedure SegSetByte(var S: TSegBuffer; Offset: LongInt; Val: Byte);
begin
  S.Blocks[Offset shr 15]^[Offset and $7FFF] := Val;
end;

function SegGetByte(var S: TSegBuffer; Offset: LongInt): Byte;
begin
  SegGetByte := S.Blocks[Offset shr 15]^[Offset and $7FFF];
end;

function SegReadWordBE(var S: TSegBuffer; Offset: LongInt): Word;
begin
  SegReadWordBE := (Word(SegGetByte(S, Offset)) shl 8) or SegGetByte(S, Offset + 1);
end;

function SegReadLongBE(var S: TSegBuffer; Offset: LongInt): LongInt;
begin
  SegReadLongBE := (LongInt(SegGetByte(S, Offset)) shl 24) or
                   (LongInt(SegGetByte(S, Offset + 1)) shl 16) or
                   (LongInt(SegGetByte(S, Offset + 2)) shl 8) or
                   LongInt(SegGetByte(S, Offset + 3));
end;

function SegCheckString(var S: TSegBuffer; Offset: LongInt; const Str: string): Boolean;
var
  I, L: Integer;
begin
  SegCheckString := False;
  L := Length(Str);
  if (Offset < 0) or (Offset + L > S.TotalSize) then Exit;
  for I := 1 to L do
  begin
    if SegGetByte(S, Offset + I - 1) <> Byte(Str[I]) then Exit;
  end;
  SegCheckString := True;
end;

function SegLoadFromFile(var S: TSegBuffer; const FileName: string): Boolean;
var
  F: file;
  Total, Left, Chunk: LongInt;
  NumRead: Word;
  BlockIdx: Integer;
begin
  SegLoadFromFile := False;
  if IOResult <> 0 then ;
  Assign(F, FileName);
  Reset(F, 1);
  if IOResult <> 0 then Exit;
  Total := FileSize(F);
  if not SegAllocate(S, Total) then begin Close(F); if IOResult <> 0 then ; Exit; end;
  Left := Total;
  BlockIdx := 0;
  while Left > 0 do
  begin
    if Left > 32768 then Chunk := 32768 else Chunk := Left;
    BlockRead(F, S.Blocks[BlockIdx]^, Chunk, NumRead);
    if IOResult <> 0 then Break;
    Dec(Left, NumRead);
    Inc(BlockIdx);
    if NumRead = 0 then Break;
  end;
  Close(F);
  if IOResult <> 0 then ;
  SegLoadFromFile := (Left = 0);
end;

function SegSaveToFile(var S: TSegBuffer; const FileName: string; Count: LongInt): Boolean;
var
  F: file;
  Left, Chunk: LongInt;
  NumWritten: Word;
  BlockIdx: Integer;
begin
  SegSaveToFile := False;
  if IOResult <> 0 then ;
  Assign(F, FileName);
  Erase(F);
  if IOResult <> 0 then ;
  Assign(F, FileName);
  Rewrite(F, 1);
  if IOResult <> 0 then Exit;
  Left := Count;
  BlockIdx := 0;
  while Left > 0 do
  begin
    if Left > 32768 then Chunk := 32768 else Chunk := Left;
    BlockWrite(F, S.Blocks[BlockIdx]^, Chunk, NumWritten);
    if IOResult <> 0 then Break;
    Dec(Left, NumWritten);
    Inc(BlockIdx);
    if NumWritten = 0 then Break;
  end;
  Close(F);
  if IOResult <> 0 then ;
  SegSaveToFile := (Left = 0);
end;

{ =============================================================================
  Packer Detection
  ============================================================================= }

function DetectBufferPacker(var InBuf: TSegBuffer): string;
var
  Size, Off: LongInt;
  W: Word;
begin
  DetectBufferPacker := '';
  Size := InBuf.TotalSize;
  if Size < 4 then Exit;

  { 1. Degas Elite (.PC1 / .PC2 / .PC3) }
  W := SegReadWordBE(InBuf, 0);
  if W = $8000 then
  begin
    DetectBufferPacker := 'Degas Elite PC1';
    Exit;
  end;
  if W = $8001 then
  begin
    DetectBufferPacker := 'Degas Elite PC2';
    Exit;
  end;
  if W = $8002 then
  begin
    DetectBufferPacker := 'Degas Elite PC3';
    Exit;
  end;

  { 2. Titus (.PC1) }
  if (Size >= 10) and ((SegGetByte(InBuf, 0) = 1) or (SegGetByte(InBuf, 0) = 2)) and
     (SegGetByte(InBuf, 1) = 0) then
  begin
    DetectBufferPacker := 'Titus PC1';
    Exit;
  end;

    { STAD Monochrome Picture }
  if SegCheckString(InBuf, 0, 'pM85') or SegCheckString(InBuf, 0, 'pM86') then
  begin
    DetectBufferPacker := 'STAD Image';
    Exit;
  end;

{ 3. Rob Northen Compression (RNC) }
  if SegCheckString(InBuf, 0, 'RNC' + #1) then
  begin
    DetectBufferPacker := 'Rob Northen RNC1';
    Exit;
  end;
  if SegCheckString(InBuf, 0, 'RNC' + #2) then
  begin
    DetectBufferPacker := 'Rob Northen RNC2';
    Exit;
  end;

  { 4. Automation Packer }
  if SegCheckString(InBuf, 0, 'LSD!') or SegCheckString(InBuf, 0, 'LSD$') or
     SegCheckString(InBuf, 0, 'AUTM') or SegCheckString(InBuf, 0, 'AU5!') or
     SegCheckString(InBuf, 0, 'LSDC') or SegCheckString(InBuf, 0, 'AU5C') then
  begin
    DetectBufferPacker := 'Automation Packer';
    Exit;
  end;

  { 5. Atomik Cruncher }
  if SegCheckString(InBuf, 0, 'ATM5') then
  begin
    DetectBufferPacker := 'Atomik Cruncher v3.5';
    Exit;
  end;
  if SegCheckString(InBuf, 0, 'ATM3') then
  begin
    DetectBufferPacker := 'Atomik Cruncher v3.1';
    Exit;
  end;
  if SegCheckString(InBuf, 0, 'ATOM') then
  begin
    DetectBufferPacker := 'Atomik / Thunder Raw';
    Exit;
  end;

  { 6. Pack-Ice Raw }
  if SegCheckString(InBuf, 0, 'ICE!') or SegCheckString(InBuf, 0, 'Ice!') or
     SegCheckString(InBuf, 0, 'TSM!') then
  begin
    DetectBufferPacker := 'Pack-Ice v2.4';
    Exit;
  end;

    { FIRE Packer Raw }
  if SegCheckString(InBuf, 0, 'FIRE') or SegCheckString(InBuf, 0, 'Fire') then
  begin
    DetectBufferPacker := 'FIRE Packer';
    Exit;
  end;

  { PowerPacker Raw }
  if SegCheckString(InBuf, 0, 'PP20') or SegCheckString(InBuf, 0, 'PX20') then
  begin
    DetectBufferPacker := 'PowerPacker';
    Exit;
  end;

  { JAM / LZH / LZW Raw }
  if SegCheckString(InBuf, 0, 'LZH!') or SegCheckString(InBuf, 0, 'LZW!') then
  begin
    DetectBufferPacker := 'JAM Packer';
    Exit;
  end;

  { Crunch-Mania Raw }
  if SegCheckString(InBuf, 0, 'CrM!') or SegCheckString(InBuf, 0, 'CrM2') or
     SegCheckString(InBuf, 0, 'DCS!') or SegCheckString(InBuf, 0, 'MSS!') then
  begin
    DetectBufferPacker := 'Crunch-Mania';
    Exit;
  end;

  { Speedpacker Raw }
  if SegCheckString(InBuf, 0, 'SP20') or SegCheckString(InBuf, 0, 'SPv3') then
  begin
    DetectBufferPacker := 'Speedpacker';
    Exit;
  end;

  { 7. Pompey Pirates (Raw or Executable) }
  if (Size >= 12) and (SegCheckString(InBuf, Size - 4, 'POPI') or SegCheckString(InBuf, Size - 4, 'PUFF')) then
  begin
    DetectBufferPacker := 'Pompey Pirates';
    Exit;
  end;
  if (Size >= 28) and (W = $601A) then
  begin
    Off := 28 + SegReadLongBE(InBuf, 2) + SegReadLongBE(InBuf, 6);
    if (Off <= Size) and (Off >= 12) and
       (SegCheckString(InBuf, Off - 4, 'POPI') or SegCheckString(InBuf, Off - 4, 'PUFF')) then
    begin
      DetectBufferPacker := 'Pompey Executable';
      Exit;
    end;
  end;

    { Sentry Raw }
  if (Size >= 12) and SegCheckString(InBuf, Size - 4, 'Snt2') then
  begin
    DetectBufferPacker := 'Sentry Data';
    Exit;
  end;

  { 4PAK Executable }
  if (Size >= 66) and (W = $601A) and (SegReadLongBE(InBuf, 58) = $4E714EF9) then
  begin
    DetectBufferPacker := '4PAK Executable';
    Exit;
  end;

  { Happy Packer Executable }
  if (Size >= 56) and (W = $601A) and SegCheckString(InBuf, 52, 'EASY') then
  begin
    DetectBufferPacker := 'Happy Packer Executable';
    Exit;
  end;

  { JEK Packer Executable }
  if (Size >= 36) and (W = $601A) and (SegReadLongBE(InBuf, 28) = $2A6F0004) and
     (SegReadLongBE(InBuf, 32) = $226D0010) then
  begin
    DetectBufferPacker := 'JEK Packer Executable';
    Exit;
  end;

  { JEK Raw Data }
  if (Size >= 4) and SegCheckString(InBuf, Size - 4, 'JEK!') then
  begin
    DetectBufferPacker := 'JEK Packer Data';
    Exit;
  end;

{ 8. Executable Headers ($601A) Scan }
  if (Size >= 28) and (W = $601A) then
  begin
    if (Size >= 450) and SegCheckString(InBuf, 442, 'ICE!') then
    begin
      DetectBufferPacker := 'Pack-Ice v2.4 PRG';
      Exit;
    end;
    if (Size >= 450) and SegCheckString(InBuf, 448, 'ICE!') then
    begin
      DetectBufferPacker := 'Pack-Ice v2.3 PRG';
      Exit;
    end;
    if (Size >= 454) and SegCheckString(InBuf, 452, 'Ice!') then
    begin
      DetectBufferPacker := 'Pack-Ice v2.2 PRG';
      Exit;
    end;
    if SegCheckString(InBuf, 28, 'Pack-Ice') or SegCheckString(InBuf, 30, 'Ice!') then
    begin
      DetectBufferPacker := 'Pack-Ice v2.1 PRG';
      Exit;
    end;

    { Scan for embedded signatures in first 2048 bytes }
    for Off := 28 to 1024 do
    begin
      if Off + 4 > Size then Break;
      if SegCheckString(InBuf, Off, 'ICE!') or SegCheckString(InBuf, Off, 'Ice!') then
      begin
        DetectBufferPacker := 'Pack-Ice Executable';
        Exit;
      end;
      if SegCheckString(InBuf, Off, 'ATOMIK') or SegCheckString(InBuf, Off, 'ATM5') then
      begin
        DetectBufferPacker := 'Atomik Executable';
        Exit;
      end;
      if SegCheckString(InBuf, Off, 'POPI') or SegCheckString(InBuf, Off, 'PUFF') then
      begin
        DetectBufferPacker := 'Pompey Executable';
        Exit;
      end;
      if SegCheckString(InBuf, Off, 'LSD!') or SegCheckString(InBuf, Off, 'AUTM') then
      begin
        DetectBufferPacker := 'Automation Executable';
        Exit;
      end;
      if SegCheckString(InBuf, Off, 'Pack-Fire') or
         SegCheckString(InBuf, Off, 'Axe/Delight') or
         SegCheckString(InBuf, Off, 'FIRE') then
      begin
        DetectBufferPacker := 'FIRE Executable';
        Exit;
      end;
      if SegCheckString(InBuf, Off, 'HAPPY') then
      begin
        DetectBufferPacker := 'Happy Packer Executable';
        Exit;
      end;
      if SegCheckString(InBuf, Off, 'JEK ') or SegCheckString(InBuf, Off, 'Byte Killer') then
      begin
        DetectBufferPacker := 'JEK Packer Executable';
        Exit;
      end;
      if SegCheckString(InBuf, Off, 'LZH!') then
      begin
        DetectBufferPacker := 'JAM LZH Executable';
        Exit;
      end;
      if SegCheckString(InBuf, Off, 'PP20') then
      begin
        DetectBufferPacker := 'PowerPacker Executable';
        Exit;
      end;
      if SegCheckString(InBuf, Off, 'Snt2') or SegCheckString(InBuf, Off, 'Sentry v2') then
      begin
        DetectBufferPacker := 'Sentry Executable';
        Exit;
      end;
      if SegCheckString(InBuf, Off, 'ATOM') then
      begin
        DetectBufferPacker := 'Thunder Executable';
        Exit;
      end;
    end;
  end;
end;

{ =============================================================================
  Pack-Ice Decompressor (v2.4 / v2.3 / v2.2 / v1.2 / Raw & Executable)
  ============================================================================= }

var
  IceInCurOff, IceInStartOff, IceOutCurOff: LongInt;
  IceBitBufContent: LongInt;
  IceBitBufLength: Integer;

function IceReadInByte(var InBuf: TSegBuffer): Byte;
begin
  if IceInCurOff <= IceInStartOff then IceReadInByte := 0
  else
  begin
    Dec(IceInCurOff);
    IceReadInByte := SegGetByte(InBuf, IceInCurOff);
  end;
end;

function IceReadInBE32(var InBuf: TSegBuffer): LongInt;
var
  B0, B1, B2, B3: Byte;
begin
  B0 := IceReadInByte(InBuf);
  B1 := IceReadInByte(InBuf);
  B2 := IceReadInByte(InBuf);
  B3 := IceReadInByte(InBuf);
  IceReadInBE32 := (LongInt(B3) shl 24) or (LongInt(B2) shl 16) or (LongInt(B1) shl 8) or LongInt(B0);
end;

function IceReadBits(var InBuf: TSegBuffer; Count: Integer): LongInt;
var
  Ret: LongInt;
  MaxCount: Integer;
begin
  Ret := 0;
  while Count > 0 do
  begin
    if IceBitBufLength = 0 then
    begin
      IceBitBufContent := IceReadInByte(InBuf);
      IceBitBufLength := 8;
    end;
    if Count < IceBitBufLength then MaxCount := Count else MaxCount := IceBitBufLength;
    Dec(IceBitBufLength, MaxCount);
    Ret := (Ret shl MaxCount) or ((IceBitBufContent shr IceBitBufLength) and ((LongInt(1) shl MaxCount) - 1));
    Dec(Count, MaxCount);
  end;
  IceReadBits := Ret;
end;

function IceReadBitsBE32(var InBuf: TSegBuffer; Count: Integer): LongInt;
var
  Ret: LongInt;
  MaxCount: Integer;
begin
  Ret := 0;
  while Count > 0 do
  begin
    if IceBitBufLength = 0 then
    begin
      IceBitBufContent := IceReadInBE32(InBuf);
      IceBitBufLength := 32;
    end;
    if Count < IceBitBufLength then MaxCount := Count else MaxCount := IceBitBufLength;
    Dec(IceBitBufLength, MaxCount);
    Ret := (Ret shl MaxCount) or ((IceBitBufContent shr IceBitBufLength) and ((LongInt(1) shl MaxCount) - 1));
    Dec(Count, MaxCount);
  end;
  IceReadBitsBE32 := Ret;
end;

procedure IceVLCInit(var V: TVLC; const Args: array of Integer; NumArgs: Integer);
var
  I, L, Val: Integer;
begin
  V.Count := NumArgs;
  L := 0;
  for I := 0 to NumArgs - 1 do
  begin
    Val := Args[I];
    if Val < 0 then
    begin
      V.BitLengths[I] := -Val;
      V.Offsets[I] := 0;
      L := 1 shl (-Val);
    end
    else
    begin
      V.BitLengths[I] := Val;
      V.Offsets[I] := L;
      L := L + (1 shl Val);
    end;
  end;
end;

function IceVLCDecode(var V: TVLC; var InBuf: TSegBuffer; Base: Integer; UseBE32: Boolean): Integer;
begin
  if UseBE32 then
    IceVLCDecode := V.Offsets[Base] + Integer(IceReadBitsBE32(InBuf, V.BitLengths[Base]))
  else
    IceVLCDecode := V.Offsets[Base] + Integer(IceReadBits(InBuf, V.BitLengths[Base]));
end;

function IceVLCDecodeCascade(var V: TVLC; var InBuf: TSegBuffer; UseBE32: Boolean): Integer;
var
  I, Len, Tmp: Integer;
begin
  IceVLCDecodeCascade := 0;
  for I := 0 to V.Count - 1 do
  begin
    Len := V.BitLengths[I];
    if UseBE32 then
      Tmp := Integer(IceReadBitsBE32(InBuf, Len))
    else
      Tmp := Integer(IceReadBits(InBuf, Len));
    if (I = V.Count - 1) or (Tmp <> (1 shl Len) - 1) then
    begin
      IceVLCDecodeCascade := V.Offsets[I] - I + Tmp;
      Exit;
    end;
  end;
end;

function DecompressPackIceStream(var InBuf: TSegBuffer; StartOffset, RawSize, InitialSrcIdx: LongInt;
                                IsOld, UseBytes: Boolean; var OutBuf: TSegBuffer): Boolean;
var
  LitVlc, CountBaseVlc, CountVlc, DistBaseVlc, DistVlc: TVLC;
  Val, Tmp: LongInt;
  Count, LitLength, CountBase, CountVal, DistBase, Distance: Integer;
  LitOldArgs: array[0..4] of Integer;
  LitNewArgs: array[0..5] of Integer;
  CountBaseArgs: array[0..3] of Integer;
  CountArgs: array[0..4] of Integer;
  DistBaseArgs: array[0..1] of Integer;
  DistArgs: array[0..2] of Integer;
begin
  DecompressPackIceStream := False;
  if not SegAllocate(OutBuf, RawSize) then Exit;
  IceInStartOff := StartOffset;
  IceInCurOff := InitialSrcIdx;
  IceOutCurOff := RawSize;
  IceBitBufLength := 0;
  IceBitBufContent := 0;

  if UseBytes then
    Val := IceReadInByte(InBuf)
  else
    Val := IceReadInBE32(InBuf);

  Tmp := Val;
  Count := 0;
  while Tmp <> 0 do
  begin
    Tmp := Tmp shl 1;
    Inc(Count);
  end;
  if Count > 0 then Dec(Count);
  if Count > 0 then
  begin
    if UseBytes then
    begin
      IceBitBufContent := Val shr (32 - Count);
      IceBitBufLength := Count - 24;
    end
    else
    begin
      IceBitBufContent := Val shr (32 - Count);
      IceBitBufLength := Count;
    end;
  end;

  if IsOld then
  begin
    LitOldArgs[0] := 1; LitOldArgs[1] := 2; LitOldArgs[2] := 2; LitOldArgs[3] := 3; LitOldArgs[4] := 10;
    IceVLCInit(LitVlc, LitOldArgs, 5);
  end
  else
  begin
    LitNewArgs[0] := 1; LitNewArgs[1] := 2; LitNewArgs[2] := 2;
    LitNewArgs[3] := 3; LitNewArgs[4] := 8; LitNewArgs[5] := 15;
    IceVLCInit(LitVlc, LitNewArgs, 6);
  end;

  CountBaseArgs[0] := 1; CountBaseArgs[1] := 1; CountBaseArgs[2] := 1; CountBaseArgs[3] := 1;
  IceVLCInit(CountBaseVlc, CountBaseArgs, 4);

  CountArgs[0] := 0; CountArgs[1] := 0; CountArgs[2] := 1; CountArgs[3] := 2; CountArgs[4] := 10;
  IceVLCInit(CountVlc, CountArgs, 5);

  DistBaseArgs[0] := 1; DistBaseArgs[1] := 1;
  IceVLCInit(DistBaseVlc, DistBaseArgs, 2);

  DistArgs[0] := 5; DistArgs[1] := 8; DistArgs[2] := 12;
  IceVLCInit(DistVlc, DistArgs, 3);

  while True do
  begin
    if (UseBytes and (IceReadBits(InBuf, 1) = 1)) or ((not UseBytes) and (IceReadBitsBE32(InBuf, 1) = 1)) then
    begin
      if UseBytes then
        LitLength := IceVLCDecodeCascade(LitVlc, InBuf, False) + 1
      else
        LitLength := IceVLCDecodeCascade(LitVlc, InBuf, True) + 1;

      for Count := 1 to LitLength do
      begin
        if IceOutCurOff <= 0 then Break;
        Dec(IceOutCurOff);
        SegSetByte(OutBuf, IceOutCurOff, IceReadInByte(InBuf));
      end;
    end;
    if IceOutCurOff <= 0 then Break;

    if UseBytes then
    begin
      CountBase := IceVLCDecodeCascade(CountBaseVlc, InBuf, False);
      CountVal := IceVLCDecode(CountVlc, InBuf, CountBase, False) + 2;
      if CountVal = 2 then
      begin
        if IceReadBits(InBuf, 1) = 1 then
          Distance := Integer(IceReadBits(InBuf, 9)) + $40
        else
          Distance := Integer(IceReadBits(InBuf, 6));
        Inc(Distance, CountVal - 1);
      end
      else
      begin
        DistBase := IceVLCDecodeCascade(DistBaseVlc, InBuf, False);
        if DistBase < 2 then DistBase := DistBase xor 1;
        Distance := IceVLCDecode(DistVlc, InBuf, DistBase, False);
        if Distance <> 0 then Inc(Distance, CountVal - 1) else Distance := 1;
      end;
    end
    else
    begin
      CountBase := IceVLCDecodeCascade(CountBaseVlc, InBuf, True);
      CountVal := IceVLCDecode(CountVlc, InBuf, CountBase, True) + 2;
      if CountVal = 2 then
      begin
        if IceReadBitsBE32(InBuf, 1) = 1 then
          Distance := Integer(IceReadBitsBE32(InBuf, 9)) + $40
        else
          Distance := Integer(IceReadBitsBE32(InBuf, 6));
        Inc(Distance, CountVal);
      end
      else
      begin
        DistBase := IceVLCDecodeCascade(DistBaseVlc, InBuf, True);
        if DistBase < 2 then DistBase := DistBase xor 1;
        Distance := IceVLCDecode(DistVlc, InBuf, DistBase, True);
        Inc(Distance, CountVal);
      end;
    end;

    for Count := 1 to CountVal do
    begin
      if IceOutCurOff <= 0 then Break;
      Dec(IceOutCurOff);
      SegSetByte(OutBuf, IceOutCurOff, SegGetByte(OutBuf, IceOutCurOff + Distance));
    end;
    if IceOutCurOff <= 0 then Break;
  end;

  DecompressPackIceStream := (IceOutCurOff = 0);
end;

function DecompressPackIce(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
const
  IceDeltas: array[0..4] of Integer = (0, -2, 2, -4, 4);
var
  InSize, Off, PackedSize, OrigSize, EndIdx, DIdx: LongInt;
  IsOld, UseBytes: Boolean;
begin
  DecompressPackIce := False;
  InSize := InBuf.TotalSize;
  if InSize < 12 then Exit;

  { Scan for ICE!, Ice! or TSM! header }
  for Off := 0 to 1024 do
  begin
    if Off + 12 > InSize then Break;
    if SegCheckString(InBuf, Off, 'ICE!') or SegCheckString(InBuf, Off, 'Ice!') or
       SegCheckString(InBuf, Off, 'TSM!') then
    begin
      PackedSize := SegReadLongBE(InBuf, Off + 4);
      OrigSize := SegReadLongBE(InBuf, Off + 8);
      if (PackedSize > 0) and (PackedSize <= InSize) and (OrigSize > 0) and (OrigSize < 524288) then
      begin
        { 1. Try canonical Off + PackedSize + Deltas FIRST }
        for DIdx := 0 to 4 do
        begin
          EndIdx := Off + PackedSize + IceDeltas[DIdx];
          if (EndIdx > Off + 12) and (EndIdx <= InSize) then
          begin
            for IsOld := False to True do
              for UseBytes := False to True do
              begin
                if DecompressPackIceStream(InBuf, Off + 12, OrigSize, EndIdx, IsOld, UseBytes, OutBuf) then
                begin
                  DecompressPackIce := True;
                  Exit;
                end;
                SegFree(OutBuf);
              end;
          end;
        end;

        { 2. Fallback: Try InSize and trailing deltas }
        for DIdx := 0 to 4 do
        begin
          EndIdx := InSize + IceDeltas[DIdx];
          if (EndIdx > Off + 12) and (EndIdx <= InSize) then
          begin
            for IsOld := False to True do
              for UseBytes := False to True do
              begin
                if DecompressPackIceStream(InBuf, Off + 12, OrigSize, EndIdx, IsOld, UseBytes, OutBuf) then
                begin
                  DecompressPackIce := True;
                  Exit;
                end;
                SegFree(OutBuf);
              end;
          end;
        end;
      end;
    end;
  end;
end;

{ =============================================================================
  Rob Northen Compression (RNC Method 1 & 2)
  ============================================================================= }

var
  RNCInPos, RNCInEnd, RNCOutPos, RNCProcessed, RNCBitCount: LongInt;
  RNCBitBuf: LongInt;
  RNCCurKey: Word;

function RNCPeek(var InBuf: TSegBuffer; Offset: LongInt): Byte;
var Idx: LongInt;
begin
  Idx := RNCInPos + Offset;
  if (Idx >= 0) and (Idx < RNCInEnd) then
    RNCPeek := SegGetByte(InBuf, Idx)
  else
    RNCPeek := 0;
end;

function RNCReadByte(var InBuf: TSegBuffer): Byte;
begin
  if RNCInPos < RNCInEnd then
  begin
    RNCReadByte := SegGetByte(InBuf, RNCInPos);
    Inc(RNCInPos);
  end
  else
  begin
    Inc(RNCInPos);
    RNCReadByte := 0;
  end;
end;

function RNCReadBitsM1(var InBuf: TSegBuffer; Count: Integer): LongInt;
var
  Bits, PrevBits: LongInt;
  B1, B2, LoByte, HiByte: Byte;
  I: Integer;
begin
  Bits := 0;
  PrevBits := 1;
  for I := 1 to Count do
  begin
    if RNCBitCount = 0 then
    begin
      B1 := RNCPeek(InBuf, 0); Inc(RNCInPos);
      B2 := RNCPeek(InBuf, 0); Inc(RNCInPos);
      LoByte := RNCPeek(InBuf, 0);
      HiByte := RNCPeek(InBuf, 1);
      RNCBitBuf := (LongInt(HiByte) shl 24) or (LongInt(LoByte) shl 16) or (LongInt(B2) shl 8) or LongInt(B1);
      RNCBitCount := 16;
    end;

    if (RNCBitBuf and 1) <> 0 then
      Bits := Bits or PrevBits;

    RNCBitBuf := (RNCBitBuf shr 1) and $7FFFFFFF;
    PrevBits := PrevBits shl 1;
    Dec(RNCBitCount);
  end;
  RNCReadBitsM1 := Bits;
end;

function InverseBits(Value: LongInt; Count: Integer): Word;
var
  Res: Word;
  I: Integer;
begin
  Res := 0;
  for I := 1 to Count do
  begin
    Res := Res shl 1;
    if (Value and 1) <> 0 then Res := Res or 1;
    Value := Value shr 1;
  end;
  InverseBits := Res;
end;

procedure MakeHufTable(var InBuf: TSegBuffer; var Table: TRNCHufTable);
var
  LeafNodes, I, BitsCount: Integer;
  BitDepths: array[0..15] of Byte;
  Val, DivVal: LongInt;
begin
  FillChar(Table, SizeOf(Table), 0);
  FillChar(BitDepths, SizeOf(BitDepths), 0);
  LeafNodes := Integer(RNCReadBitsM1(InBuf, 5));
  if LeafNodes = 0 then Exit;
  if LeafNodes > 16 then LeafNodes := 16;

  for I := 0 to LeafNodes - 1 do
    BitDepths[I] := Byte(RNCReadBitsM1(InBuf, 4));

  Val := 0;
  DivVal := $40000000;
  for BitsCount := 1 to 16 do
  begin
    for I := 0 to LeafNodes - 1 do
    begin
      if BitDepths[I] = BitsCount then
      begin
        Table[I].Depth := BitsCount;
        Table[I].Code := InverseBits(Val div DivVal, BitsCount);
        Inc(Val, DivVal);
      end;
    end;
    DivVal := DivVal shr 1;
  end;
end;

function DecodeTableData(var InBuf: TSegBuffer; var Table: TRNCHufTable; var DecVal: LongInt): Boolean;
var
  I: Integer;
  Mask: LongInt;
begin
  DecodeTableData := False;
  for I := 0 to 15 do
  begin
    if Table[I].Depth > 0 then
    begin
      Mask := (LongInt(1) shl Table[I].Depth) - 1;
      if Table[I].Code = Word(RNCBitBuf and Mask) then
      begin
        RNCReadBitsM1(InBuf, Table[I].Depth);
        if I < 2 then
          DecVal := I
        else
          DecVal := RNCReadBitsM1(InBuf, I - 1) or (LongInt(1) shl (I - 1));
        DecodeTableData := True;
        Exit;
      end;
    end;
  end;
  DecVal := 0;
end;

function Ror16(Key: Word): Word;
begin
  if (Key and 1) <> 0 then
    Ror16 := $8000 or (Key shr 1)
  else
    Ror16 := Key shr 1;
end;

function DecompressRNCMethod1(var InBuf: TSegBuffer; OutSize: LongInt; var OutBuf: TSegBuffer): Boolean;
var
  RawTable, LenTable, PosTable: TRNCHufTable;
  Subchunks, SC, I: Integer;
  DataLen, MatchOffset, MatchCount: LongInt;
  LoopGuard: LongInt;
  Hi, Mid, Lo, B: Byte;
begin
  DecompressRNCMethod1 := False;
  if not SegAllocate(OutBuf, OutSize) then Exit;
  RNCInPos := 18;
  RNCInEnd := InBuf.TotalSize;
  RNCOutPos := 0;
  RNCProcessed := 0;
  RNCBitBuf := 0;
  RNCBitCount := 0;
  RNCCurKey := 0;
  LoopGuard := 0;

  { Skip 2 lock bits }
  RNCReadBitsM1(InBuf, 2);

  while (RNCProcessed < OutSize) and (RNCInPos < RNCInEnd + 16) do
  begin
    Inc(LoopGuard);
    if LoopGuard > 20000 then Break;

    RNCCurKey := 0;
    MakeHufTable(InBuf, RawTable);
    MakeHufTable(InBuf, LenTable);
    MakeHufTable(InBuf, PosTable);

    Subchunks := Integer(RNCReadBitsM1(InBuf, 16));
    if Subchunks <= 0 then Break;

    for SC := 0 to Subchunks - 1 do
    begin
      if not DecodeTableData(InBuf, RawTable, DataLen) then Exit;
      Inc(RNCProcessed, DataLen);

      if DataLen > 0 then
      begin
        for I := 1 to DataLen do
        begin
          B := RNCReadByte(InBuf);
          if RNCOutPos < OutSize then
          begin
            SegSetByte(OutBuf, RNCOutPos, (RNCCurKey xor B) and $FF);
            Inc(RNCOutPos);
          end;
        end;
        RNCCurKey := Ror16(RNCCurKey);

        Hi := RNCPeek(InBuf, 2);
        Mid := RNCPeek(InBuf, 1);
        Lo := RNCPeek(InBuf, 0);
        RNCBitBuf := (((LongInt(Hi) shl 16) or (LongInt(Mid) shl 8) or LongInt(Lo)) shl RNCBitCount) or
                     (RNCBitBuf and ((LongInt(1) shl RNCBitCount) - 1));
      end;

      if SC < Subchunks - 1 then
      begin
        if not DecodeTableData(InBuf, LenTable, MatchOffset) then Exit;
        Inc(MatchOffset, 1);

        if not DecodeTableData(InBuf, PosTable, MatchCount) then Exit;
        Inc(MatchCount, 2);

        Inc(RNCProcessed, MatchCount);

        for I := 1 to MatchCount do
        begin
          if (RNCOutPos < OutSize) and (RNCOutPos - MatchOffset >= 0) then
          begin
            SegSetByte(OutBuf, RNCOutPos, SegGetByte(OutBuf, RNCOutPos - MatchOffset));
            Inc(RNCOutPos);
          end
          else Break;
        end;
      end;

      if RNCProcessed >= OutSize then Break;
    end;
  end;

  DecompressRNCMethod1 := (RNCOutPos = OutSize);
end;

function DecompressRNC(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
var
  Method: Byte;
  OutSize: LongInt;
begin
  DecompressRNC := False;
  if InBuf.TotalSize < 18 then Exit;
  if not (SegCheckString(InBuf, 0, 'RNC' + #1) or SegCheckString(InBuf, 0, 'RNC' + #2)) then Exit;

  Method := SegGetByte(InBuf, 3);
  OutSize := SegReadLongBE(InBuf, 4);
  if (OutSize <= 0) or (OutSize > 524288) then Exit;

  if Method = 1 then
    DecompressRNC := DecompressRNCMethod1(InBuf, OutSize, OutBuf)
  else
    DecompressRNC := False; { Method 2 fallback }
end;

{ =============================================================================
  Atomik Cruncher (v3.5 / v3.1 / ATM5 / ATM3 / ATOM)
  ============================================================================= }

function DecompressAtomik(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
var
  AtmPos, SearchIdx, K, I, J: LongInt;
  OrigSize, PackedSize, DataOffset: LongInt;
  IsPRG, IsV31: Boolean;
  Sig: LongInt;
  DstIdx, SrcIdx, BlockSize, BlockTarget, LengthBits, MatchOffset: LongInt;
  OffsetIdx, LenVal, MatchLen, QIdx: LongInt;
  PicCnt, Cmd, Mask, SubVal: Byte;
  SpecialOffsetTabFull, ShortCharTabFull: Boolean;
  SpecialOffset: Byte;
  SpecialOffsetTab: array[0..6] of Integer;
  ShortCharTab: array[0..15] of Byte;
  BitTable, OffsetTable: array[0..7] of Integer;
  Plane0, Plane1, Plane2, Plane3, DataByte: Word;
  PicOffset, P: LongInt;

  function AtomReadByte: Byte;
  begin
    if SrcIdx <= DataOffset then
    begin
      Dec(SrcIdx);
      AtomReadByte := 0;
      Exit;
    end;
    Dec(SrcIdx);
    AtomReadByte := SegGetByte(InBuf, SrcIdx);
  end;

  function AtomGetBits(BitLen: Integer): Integer;
  var Tmp: Integer;
  begin
    Tmp := 0;
    while BitLen > 0 do
    begin
      Tmp := Tmp shl 1;
      Mask := Mask shr 1;
      if Mask = 0 then
      begin
        Cmd := AtomReadByte;
        Mask := $80;
      end;
      if (Cmd and Mask) <> 0 then Tmp := Tmp or 1;
      Dec(BitLen);
    end;
    AtomGetBits := Tmp;
  end;

begin
  DecompressAtomik := False;
  if InBuf.TotalSize < 12 then Exit;

  AtmPos := -1;
  IsPRG := False;
  IsV31 := False;
  OrigSize := 0;
  PackedSize := 0;
  DataOffset := 0;

  { 1. Check Data Header ('ATM5', 'ATM3', 'ATOM') }
  for SearchIdx := 0 to 1024 do
  begin
    if SearchIdx + 12 > InBuf.TotalSize then Break;
    if SegGetByte(InBuf, SearchIdx) = Byte('A') then
    begin
      Sig := SegReadLongBE(InBuf, SearchIdx);
      if (Sig = $41544D35) or (Sig = $41544D33) or (Sig = $41544F4D) then
      begin
        OrigSize := SegReadLongBE(InBuf, SearchIdx + 4);
        PackedSize := SegReadLongBE(InBuf, SearchIdx + 8);
        if (OrigSize > 0) and (OrigSize < 524288) and (PackedSize > 0) and (PackedSize <= InBuf.TotalSize) then
        begin
          AtmPos := SearchIdx;
          DataOffset := SearchIdx + 12;
          if Sig = $41544D33 then IsV31 := True;
          Break;
        end;
      end;
    end;
  end;

  { 2. Check Packed PRG Executable ('ATOMIK') }
  if AtmPos = -1 then
  begin
    for SearchIdx := 0 to 2048 do
    begin
      if SearchIdx + 38 > InBuf.TotalSize then Break;
      if SegCheckString(InBuf, SearchIdx, 'ATOMIK') then
      begin
        for K := 0 to 19 do
        begin
          if (SearchIdx + K + 2 < InBuf.TotalSize) and
             (SegGetByte(InBuf, SearchIdx + K) = Byte('3')) and
             (SegGetByte(InBuf, SearchIdx + K + 1) = Byte('.')) and
             (SegGetByte(InBuf, SearchIdx + K + 2) = Byte('1')) then
          begin
            IsV31 := True;
            Break;
          end;
        end;

        if IsV31 then
        begin
          OrigSize := SegReadLongBE(InBuf, SearchIdx + 22);
          PackedSize := SegReadLongBE(InBuf, SearchIdx + 26);
          DataOffset := SearchIdx + 30;
        end
        else
        begin
          OrigSize := SegReadLongBE(InBuf, SearchIdx + 30);
          PackedSize := SegReadLongBE(InBuf, SearchIdx + 34);
          DataOffset := SearchIdx + 38;
        end;

        if (OrigSize > 0) and (OrigSize < 524288) and (PackedSize > 0) then
        begin
          AtmPos := SearchIdx;
          IsPRG := True;
          Break;
        end;
      end;
    end;
  end;

  if (AtmPos = -1) or (OrigSize = 0) then Exit;
  if not SegAllocate(OutBuf, OrigSize) then Exit;

  DstIdx := OrigSize;
  SrcIdx := DataOffset + PackedSize;
  if SrcIdx > InBuf.TotalSize then SrcIdx := InBuf.TotalSize;

  PicCnt := 0;
  Cmd := 0;
  if IsPRG then
    Cmd := AtomReadByte
  else
  begin
    PicCnt := AtomReadByte;
    Cmd := AtomReadByte;
  end;

  while (Cmd = 0) and (SrcIdx > DataOffset) do
  begin
    if not IsPRG then PicCnt := Cmd;
    Cmd := AtomReadByte;
  end;

  Mask := $80;
  while ((Cmd and 1) = 0) and (Mask > 0) do
  begin
    Cmd := Cmd shr 1;
    Mask := Mask shr 1;
  end;
  Cmd := Cmd shr 1;

  OffsetTable[0] := 0;    OffsetTable[1] := 32;   OffsetTable[2] := 96;   OffsetTable[3] := 352;
  OffsetTable[4] := 864;  OffsetTable[5] := 1888; OffsetTable[6] := 3936; OffsetTable[7] := 8032;

  if IsV31 then
  begin
    BitTable[0] := 5; BitTable[1] := 6; BitTable[2] := 8; BitTable[3] := 9;
    BitTable[4] := 10; BitTable[5] := 11; BitTable[6] := 12; BitTable[7] := 13;
  end
  else
  begin
    BitTable[0] := 1; BitTable[1] := 2; BitTable[2] := 4; BitTable[3] := 5;
    BitTable[4] := 6; BitTable[5] := 7; BitTable[6] := 8; BitTable[7] := 9;
  end;

  while (DstIdx > 0) and (SrcIdx >= DataOffset - 16) do
  begin
    SpecialOffsetTabFull := False;
    ShortCharTabFull := False;

    if not IsV31 then
    begin
      if AtomGetBits(1) = 1 then
      begin
        SpecialOffset := AtomReadByte;
        K := 1;
        for I := 0 to 6 do
        begin
          if K = SpecialOffset then Inc(K, 2);
          SpecialOffsetTab[I] := K;
          Inc(K, 2);
        end;
        SpecialOffsetTabFull := True;
      end;

      if AtomGetBits(1) = 1 then
      begin
        for I := 0 to 15 do ShortCharTab[I] := AtomReadByte;
        ShortCharTabFull := True;
      end;
    end;

    LengthBits := AtomReadByte;
    BlockSize := (LongInt(AtomReadByte) shl 8) or AtomReadByte;
    if (BlockSize = 0) and (SrcIdx <= DataOffset) then Break;
    if DstIdx < BlockSize then BlockSize := DstIdx;
    BlockTarget := DstIdx - BlockSize;

    while (DstIdx > BlockTarget) and (SrcIdx >= DataOffset - 16) do
    begin
      if AtomGetBits(1) = 0 then
      begin
        Dec(DstIdx);
        SegSetByte(OutBuf, DstIdx, AtomReadByte);
      end
      else
      begin
        LenVal := 0;
        while AtomGetBits(1) = 0 do
        begin
          if LenVal = LengthBits then
          begin
            if IsV31 then
            begin
              if AtomGetBits(1) = 1 then Inc(LenVal, 1)
              else
              begin
                K := AtomGetBits(4);
                if K = 0 then K := AtomGetBits(8) + 15;
                Inc(LenVal, K);
              end;
            end
            else
            begin
              K := AtomGetBits(4);
              if K = 0 then
              begin
                K := AtomGetBits(8);
                if K = 0 then K := AtomGetBits(14) + 255;
                Inc(K, 15);
              end;
              Inc(LenVal, K);
            end;
            Break;
          end;
          Inc(LenVal);
        end;

        if LenVal = 0 then
        begin
          if AtomGetBits(1) = 1 then
          begin
            K := AtomGetBits(4);
            Dec(DstIdx);
            if ShortCharTabFull then
              SegSetByte(OutBuf, DstIdx, ShortCharTab[K])
            else
            begin
              SubVal := K;
              if SubVal > 7 then Inc(SubVal, $F0);
              if DstIdx + 1 < OrigSize then
                SegSetByte(OutBuf, DstIdx, Byte((Integer(SegGetByte(OutBuf, DstIdx + 1)) - SubVal) and $FF))
              else
                SegSetByte(OutBuf, DstIdx, Byte((-SubVal) and $FF));
            end;
            Continue;
          end
          else
          begin
            MatchLen := 2;
            OffsetIdx := AtomGetBits(2);
          end;
        end
        else
        begin
          MatchLen := LenVal + 2;
          OffsetIdx := AtomGetBits(3);
        end;

        if OffsetIdx > 7 then Exit;

        if IsV31 then
          MatchOffset := OffsetTable[OffsetIdx] + AtomGetBits(BitTable[OffsetIdx])
        else
        begin
          if SpecialOffsetTabFull then
          begin
            K := AtomGetBits(BitTable[OffsetIdx]) shl 4;
            I := AtomGetBits(3);
            if I = 7 then
            begin
              if AtomGetBits(1) = 1 then
                K := K or ((AtomGetBits(3) * 2) and $FF)
              else
                K := K or SpecialOffset;
            end
            else if (I >= 0) and (I < 7) then
              K := K or SpecialOffsetTab[I];
            MatchOffset := OffsetTable[OffsetIdx] + K;
          end
          else
            MatchOffset := OffsetTable[OffsetIdx] + AtomGetBits(BitTable[OffsetIdx] + 4);
        end;

        QIdx := DstIdx + MatchOffset + 1;
        if DstIdx - BlockTarget < MatchLen then MatchLen := DstIdx - BlockTarget;

        while MatchLen > 0 do
        begin
          Dec(DstIdx);
          Dec(QIdx);
          if (QIdx >= 0) and (QIdx < OrigSize) then
            SegSetByte(OutBuf, DstIdx, SegGetByte(OutBuf, QIdx))
          else
            SegSetByte(OutBuf, DstIdx, 0);
          Dec(MatchLen);
        end;
      end;
    end;
  end;

  { Planar restoration for ST screens }
  while (PicCnt > 0) and (OutBuf.TotalSize > 32000) do
  begin
    PicOffset := SegReadLongBE(OutBuf, OutBuf.TotalSize - 4);
    if PicOffset > OutBuf.TotalSize - 32000 then PicOffset := OutBuf.TotalSize - 32000;
    if PicOffset < 0 then PicOffset := 0;

    P := PicOffset;
    for I := 1 to 4000 do
    begin
      Plane0 := 0; Plane1 := 0; Plane2 := 0; Plane3 := 0;
      for J := 0 to 7 do
      begin
        DataByte := SegGetByte(OutBuf, P + J);
        Plane0 := Plane0 shl 2; Plane1 := Plane1 shl 2; Plane2 := Plane2 shl 2; Plane3 := Plane3 shl 2;
        Inc(Plane3, DataByte and 1); DataByte := DataByte shr 1;
        Inc(Plane2, DataByte and 1); DataByte := DataByte shr 1;
        Inc(Plane1, DataByte and 1); DataByte := DataByte shr 1;
        Inc(Plane0, DataByte and 1);
        Inc(Plane3, DataByte and 2); DataByte := DataByte shr 1;
        Inc(Plane2, DataByte and 2); DataByte := DataByte shr 1;
        Inc(Plane1, DataByte and 2); DataByte := DataByte shr 1;
        Inc(Plane0, DataByte and 2);
      end;
      SegSetByte(OutBuf, P, (Plane0 shr 8) and $FF); Inc(P);
      SegSetByte(OutBuf, P, Plane0 and $FF); Inc(P);
      SegSetByte(OutBuf, P, (Plane1 shr 8) and $FF); Inc(P);
      SegSetByte(OutBuf, P, Plane1 and $FF); Inc(P);
      SegSetByte(OutBuf, P, (Plane2 shr 8) and $FF); Inc(P);
      SegSetByte(OutBuf, P, Plane2 and $FF); Inc(P);
      SegSetByte(OutBuf, P, (Plane3 shr 8) and $FF); Inc(P);
      SegSetByte(OutBuf, P, Plane3 and $FF); Inc(P);
    end;
    Dec(PicCnt);
  end;

  DecompressAtomik := (DstIdx = 0);
end;

{ =============================================================================
  Pompey Pirates Decompressor (v1.5 / v1.9 / v2.3 / POPI / PUFF)
  ============================================================================= }

function DecompressPompey(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
var
  PayloadStart, PayloadEnd: LongInt;
  UncompressedLen, PackedLen: LongInt;
  InPos, OutPos: LongInt;
  BitBuf, Extend: Byte;
  BranchOnCarrySet: Boolean;
  TextLen, DataLen, DataEnd: LongInt;

  function PmpGetBit: Byte;
  var Carry, NewByte, NewCarry: Byte;
  begin
    Carry := BitBuf and 1;
    BitBuf := BitBuf shr 1;
    if BitBuf <> 0 then
    begin
      Extend := Carry;
      PmpGetBit := Carry;
      Exit;
    end;
    Extend := Carry;
    if InPos <= PayloadStart then
    begin
      BitBuf := 0;
      PmpGetBit := 0;
      Exit;
    end;
    Dec(InPos);
    NewByte := SegGetByte(InBuf, InPos);
    NewCarry := NewByte and 1;
    BitBuf := (NewByte shr 1) or (Extend shl 7);
    Extend := NewCarry;
    PmpGetBit := NewCarry;
  end;

  function PmpReadBits(Count: Integer): LongInt;
  var I: Integer; Res: LongInt;
  begin
    Res := 0;
    for I := 1 to Count do
      Res := (Res shl 1) or LongInt(PmpGetBit);
    PmpReadBits := Res;
  end;

  function PmpSubE0(D4: Byte; var IsZero: Boolean): LongInt;
  var D2, D1: LongInt;
  begin
    D2 := PmpReadBits(2);
    D1 := ((D2 + 1) * 4) - 1;
    if ((D4 xor Byte(D1)) and $FF) <> 0 then
    begin
      D2 := PmpReadBits(D1 + 1);
      IsZero := (D2 = 0);
      PmpSubE0 := D2;
    end
    else
    begin
      IsZero := True;
      PmpSubE0 := D2;
    end;
  end;

  function PmpSubDE: LongInt;
  var Dummy: Boolean;
  begin
    PmpSubDE := PmpSubE0(0, Dummy);
  end;

  function DoDecompress(ABranchOnCarrySet: Boolean): Boolean;
  var
    D3, Offset, Shift, Res, D2, NumBits: LongInt;
    I: Integer;
    Bit5: Byte;
    TakeBranch, IsZero: Boolean;
  begin
    DoDecompress := False;
    InPos := PayloadEnd - 12;
    if InPos <= PayloadStart then Exit;

    Dec(InPos);
    BitBuf := SegGetByte(InBuf, InPos);
    while (BitBuf = 0) do
    begin
      if InPos <= PayloadStart then Exit;
      Dec(InPos);
      BitBuf := SegGetByte(InBuf, InPos);
    end;

    Extend := 0;
    OutPos := UncompressedLen;

    while OutPos > 0 do
    begin
      if PmpGetBit = 0 then
      begin
        if InPos <= PayloadStart then Exit;
        Dec(InPos);
        Dec(OutPos);
        SegSetByte(OutBuf, OutPos, SegGetByte(InBuf, InPos));
        Continue;
      end;

      if PmpGetBit = 0 then
      begin
        if PmpGetBit = 1 then
        begin
          D3 := 1;
          if InPos <= PayloadStart then Exit;
          Dec(InPos);
          Offset := SegGetByte(InBuf, InPos);
        end
        else
        begin
          D2 := PmpReadBits(2);
          if D2 = 0 then
          begin
            D3 := PmpSubDE;
            Offset := 1;
          end
          else
          begin
            NumBits := (D2 + 1) * 2;
            D3 := PmpReadBits(NumBits);
            Offset := PmpSubDE;
          end;
        end;

        if (Offset = 0) or (OutPos + Offset > UncompressedLen) then Exit;
        for I := 0 to Integer(D3) do
        begin
          if OutPos = 0 then Exit;
          Dec(OutPos);
          SegSetByte(OutBuf, OutPos, SegGetByte(OutBuf, OutPos + Offset));
        end;
        Continue;
      end;

      if PmpGetBit = 0 then
      begin
        Res := PmpSubE0($0F, IsZero);
        if not IsZero then
        begin
          Offset := Res;
          D3 := 2;
          if (Offset = 0) or (OutPos + Offset > UncompressedLen) then Exit;
          for I := 0 to Integer(D3) do
          begin
            if OutPos = 0 then Exit;
            Dec(OutPos);
            SegSetByte(OutBuf, OutPos, SegGetByte(OutBuf, OutPos + Offset));
          end;
        end
        else
        begin
          if OutPos = 0 then Exit;
          Dec(OutPos);
          SegSetByte(OutBuf, OutPos, 0);
        end;
        Continue;
      end;

      if PmpGetBit = 0 then
      begin
        Shift := PmpReadBits(3);
        if OutPos = 0 then Exit;
        Dec(OutPos);
        SegSetByte(OutBuf, OutPos, Byte(1 shl Shift));
        Continue;
      end;

      Bit5 := PmpGetBit;
      if ABranchOnCarrySet then TakeBranch := (Bit5 = 1) else TakeBranch := (Bit5 = 0);

      if TakeBranch then
      begin
        D3 := 4;
        Offset := PmpSubDE;
        if (Offset = 0) or (OutPos + Offset > UncompressedLen) then Exit;
        for I := 0 to Integer(D3) do
        begin
          if OutPos = 0 then Exit;
          Dec(OutPos);
          SegSetByte(OutBuf, OutPos, SegGetByte(OutBuf, OutPos + Offset));
        end;
        Continue;
      end;

      Res := PmpSubE0($0F, IsZero);
      if not IsZero then
      begin
        Offset := Res;
        D3 := 3;
        if (Offset = 0) or (OutPos + Offset > UncompressedLen) then Exit;
        for I := 0 to Integer(D3) do
        begin
          if OutPos = 0 then Exit;
          Dec(OutPos);
          SegSetByte(OutBuf, OutPos, SegGetByte(OutBuf, OutPos + Offset));
        end;
      end
      else
      begin
        if (OutPos = 0) or (OutPos >= UncompressedLen) then Exit;
        Dec(OutPos);
        SegSetByte(OutBuf, OutPos, SegGetByte(OutBuf, OutPos + 1));
      end;
    end;

    DoDecompress := (OutPos = 0);
  end;

begin
  DecompressPompey := False;
  if InBuf.TotalSize < 16 then Exit;

  PayloadStart := 0;
  PayloadEnd := 0;
  BranchOnCarrySet := False;

  { 1. Check if executable ($601A) }
  if (InBuf.TotalSize >= 28) and (SegReadWordBE(InBuf, 0) = $601A) then
  begin
    TextLen := SegReadLongBE(InBuf, 2);
    DataLen := SegReadLongBE(InBuf, 6);
    DataEnd := 28 + TextLen + DataLen;
    if (DataEnd <= InBuf.TotalSize) and (DataEnd >= 12) and
       (SegCheckString(InBuf, DataEnd - 4, 'POPI') or SegCheckString(InBuf, DataEnd - 4, 'PUFF')) then
    begin
      if DataLen > 0 then
        PayloadStart := 28 + TextLen
      else
        PayloadStart := 28;
      PayloadEnd := DataEnd;
      if (InBuf.TotalSize > $86) and (SegGetByte(InBuf, $86) = $65) then
        BranchOnCarrySet := True;
    end;
  end;

  { 2. Check for POPI / PUFF at end of buffer }
  if (PayloadEnd = 0) and
     (SegCheckString(InBuf, InBuf.TotalSize - 4, 'POPI') or SegCheckString(InBuf, InBuf.TotalSize - 4, 'PUFF')) then
  begin
    PayloadStart := 0;
    PayloadEnd := InBuf.TotalSize;
  end;

  if PayloadEnd < 12 then Exit;
  UncompressedLen := SegReadLongBE(InBuf, PayloadEnd - 8);
  PackedLen := SegReadLongBE(InBuf, PayloadEnd - 12);

  if (UncompressedLen <= 0) or (UncompressedLen > 524288) then Exit;
  if not SegAllocate(OutBuf, UncompressedLen) then Exit;

  if DoDecompress(BranchOnCarrySet) then
  begin
    DecompressPompey := True;
    Exit;
  end;

  if DoDecompress(not BranchOnCarrySet) then
  begin
    DecompressPompey := True;
    Exit;
  end;

  SegFree(OutBuf);
end;

{ =============================================================================
  Automation Packer (v2.x / v3.x / v5.x / LSD! / AUTM)
  ============================================================================= }

function DecompressAutomation(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
const
  LowerTable: array[0..3] of Integer = (10, 3, 2, 2);
  UpperTable: array[0..3] of Integer = (14, 7, 4, 1);
  RepeatBits: array[0..4] of Integer = (10, 2, 1, 0, 0);
  RepeatAdj:  array[0..4] of Integer = (10, 6, 4, 3, 2);
  OffsetBits: array[0..2] of Integer = (11, 4, 7);
  OffsetAdj:  array[0..2] of Integer = (288, 0, 32);
var
  DataStart, A0, A1, A2, EndA0, D1, D2, D3, D4, D5, OffsetVal, MaskVal, I: LongInt;
  BitBuf, CarryBit: Byte;

  function AutoGetBit: Byte;
  var NextCarry: Byte;
  begin
    CarryBit := (BitBuf shr 7) and 1;
    BitBuf := (BitBuf shl 1) and $FF;
    if BitBuf = 0 then
    begin
      Dec(A0);
      if (A0 < 0) or (A0 >= InBuf.TotalSize) then
      begin
        AutoGetBit := 0;
        Exit;
      end;
      BitBuf := SegGetByte(InBuf, A0);
      NextCarry := (BitBuf shr 7) and 1;
      BitBuf := ((BitBuf shl 1) or CarryBit) and $FF;
      CarryBit := NextCarry;
    end;
    AutoGetBit := CarryBit;
  end;

  function AutoGetBits(NumBits: Integer; InitialVal: LongInt): LongInt;
  var K: Integer; Res: LongInt;
  begin
    Res := InitialVal;
    for K := 1 to NumBits do
      Res := ((Res shl 1) or AutoGetBit) and $FFFF;
    AutoGetBits := Res;
  end;

begin
  DecompressAutomation := False;
  if InBuf.TotalSize < 12 then Exit;

  DataStart := -1;
  for I := 0 to 1024 do
  begin
    if I + 12 > InBuf.TotalSize then Break;
    if (I = 0) or
       SegCheckString(InBuf, I, 'LSD!') or SegCheckString(InBuf, I, 'LSD$') or
       SegCheckString(InBuf, I, 'AUTM') or SegCheckString(InBuf, I, 'AU5!') or
       SegCheckString(InBuf, I, 'AU5C') or SegCheckString(InBuf, I, 'LSDC') then
    begin
      D5 := SegReadLongBE(InBuf, I + 4);
      D1 := SegReadLongBE(InBuf, I + 8);
      if (D1 > 0) and (D5 >= D1) and (D5 < 524288) then
      begin
        DataStart := I;
        Break;
      end;
    end;
  end;

  if DataStart = -1 then Exit;
  D5 := SegReadLongBE(InBuf, DataStart + 4);
  D1 := SegReadLongBE(InBuf, DataStart + 8);
  if (D5 <= 0) or (D5 > 524288) or (D1 <= 0) then Exit;

  if not SegAllocate(OutBuf, D5) then Exit;
  A1 := D5;
  A0 := DataStart + 8 + D1 - 4;
  Dec(A0, 2);
  if (A0 < 0) or (A0 + 2 > InBuf.TotalSize) then begin SegFree(OutBuf); Exit; end;

  if (SegReadWordBE(InBuf, A0) and $8000) <> 0 then Dec(A0, 1);
  Dec(A0);
  if (A0 < 0) or (A0 >= InBuf.TotalSize) then begin SegFree(OutBuf); Exit; end;

  BitBuf := SegGetByte(InBuf, A0);
  CarryBit := 0;
  EndA0 := DataStart + 12;

  while True do
  begin
    if AutoGetBit <> 0 then
    begin
      D1 := 0;
      if AutoGetBit <> 0 then
      begin
        D3 := 3;
        while True do
        begin
          MaskVal := (LongInt(1) shl LowerTable[D3]) - 1;
          D1 := AutoGetBits(LowerTable[D3], 0);
          if (D3 <> 0) and (D1 = MaskVal) then Dec(D3) else Break;
        end;
        Inc(D1, UpperTable[D3]);
      end;

      for I := 0 to D1 do
      begin
        Dec(A0);
        Dec(A1);
        if (A1 < 0) or (A0 < 0) or (A0 >= InBuf.TotalSize) then Break;
        SegSetByte(OutBuf, A1, SegGetByte(InBuf, A0));
      end;
    end;

    if A0 <= EndA0 then Break;

    D2 := 3;
    while True do
    begin
      if AutoGetBit = 0 then Break;
      Dec(D2);
      if D2 < 0 then Break;
    end;

    Inc(D2);
    if (D2 < 0) or (D2 > 4) then Break;
    if RepeatBits[D2] <> 0 then
      D1 := AutoGetBits(RepeatBits[D2], 0)
    else
      D1 := 0;
    Inc(D1, RepeatAdj[D2]);

    if D1 = 2 then
    begin
      if AutoGetBit = 0 then
      begin
        D3 := 5;
        D4 := 0;
      end
      else
      begin
        D3 := 8;
        D4 := 64;
      end;
      OffsetVal := AutoGetBits(D3 + 1, 0) + D4;
    end
    else
    begin
      D3 := 1;
      while True do
      begin
        if AutoGetBit = 0 then Break;
        Dec(D3);
        if D3 < 0 then Break;
      end;
      Inc(D3);
      if (D3 < 0) or (D3 > 2) then Break;
      OffsetVal := AutoGetBits(OffsetBits[D3] + 1, 0) + OffsetAdj[D3];
    end;

    A2 := A1 + OffsetVal + D1;
    if A2 > OutBuf.TotalSize then A2 := OutBuf.TotalSize;

    for I := 1 to D1 do
    begin
      Dec(A1);
      Dec(A2);
      if (A1 >= 0) and (A2 >= 0) and (A2 < OutBuf.TotalSize) then
        SegSetByte(OutBuf, A1, SegGetByte(OutBuf, A2));
    end;

    if A1 <= 0 then Break;
  end;

  DecompressAutomation := (A1 = 0);
  if A1 <> 0 then SegFree(OutBuf);
end;

{ =============================================================================
  Graphic Depackers (Degas Elite PC1 and Titus PC1)
  ============================================================================= }

function DecompressDegasPC(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
var
  SrcPos: LongInt;
  ResVal: Word;
  NumLines, NumPlanes, PlaneBytesPerLine: Integer;
  Line, Plane, PlaneBytes: Integer;
  B: Byte;
  Cnt, K: Integer;
  DestOff: LongInt;
  TempScanline: array[0..3, 0..79] of Byte;
begin
  DecompressDegasPC := False;
  if InBuf.TotalSize < 34 then Exit;
  if not SegAllocate(OutBuf, 32034) then Exit;

  ResVal := SegReadWordBE(InBuf, 0);
  case ResVal of
    $8000: begin NumLines := 200; NumPlanes := 4; PlaneBytesPerLine := 40; end;
    $8001: begin NumLines := 200; NumPlanes := 2; PlaneBytesPerLine := 80; end;
    $8002: begin NumLines := 400; NumPlanes := 1; PlaneBytesPerLine := 80; end;
  else
    Exit;
  end;

  { Write standard uncompressed DEGAS resolution word (0, 1, or 2) }
  SegSetByte(OutBuf, 0, 0);
  SegSetByte(OutBuf, 1, Byte(ResVal and $03));

  { Copy 32-byte palette }
  for K := 2 to 33 do
    SegSetByte(OutBuf, K, SegGetByte(InBuf, K));

  SrcPos := 34;

  for Line := 0 to NumLines - 1 do
  begin
    for Plane := 0 to NumPlanes - 1 do
    begin
      PlaneBytes := 0;
      while (PlaneBytes < PlaneBytesPerLine) and (SrcPos < InBuf.TotalSize) do
      begin
        B := SegGetByte(InBuf, SrcPos); Inc(SrcPos);
        if (B and $80) = 0 then
        begin
          Cnt := B + 1;
          for K := 1 to Cnt do
          begin
            if (PlaneBytes < PlaneBytesPerLine) and (SrcPos < InBuf.TotalSize) then
            begin
              TempScanline[Plane, PlaneBytes] := SegGetByte(InBuf, SrcPos);
              Inc(SrcPos);
              Inc(PlaneBytes);
            end;
          end;
        end
        else if B <> $80 then
        begin
          Cnt := (not B) + 2;
          if SrcPos < InBuf.TotalSize then
          begin
            B := SegGetByte(InBuf, SrcPos); Inc(SrcPos);
            for K := 1 to Cnt do
            begin
              if PlaneBytes < PlaneBytesPerLine then
              begin
                TempScanline[Plane, PlaneBytes] := B;
                Inc(PlaneBytes);
              end;
            end;
          end;
        end;
      end;
    end;

    { Interleave planes into authentic Atari ST display memory }
    case NumPlanes of
      4: { Low Res: 4 planes, 40 bytes/plane, 160 bytes/line }
        begin
          DestOff := 34 + LongInt(Line) * 160;
          for K := 0 to 19 do
          begin
            for Plane := 0 to 3 do
            begin
              SegSetByte(OutBuf, DestOff, TempScanline[Plane, K * 2]);
              Inc(DestOff);
              SegSetByte(OutBuf, DestOff, TempScanline[Plane, K * 2 + 1]);
              Inc(DestOff);
            end;
          end;
        end;
      2: { Med Res: 2 planes, 80 bytes/plane, 160 bytes/line }
        begin
          DestOff := 34 + LongInt(Line) * 160;
          for K := 0 to 39 do
          begin
            for Plane := 0 to 1 do
            begin
              SegSetByte(OutBuf, DestOff, TempScanline[Plane, K * 2]);
              Inc(DestOff);
              SegSetByte(OutBuf, DestOff, TempScanline[Plane, K * 2 + 1]);
              Inc(DestOff);
            end;
          end;
        end;
      1: { High Res: 1 plane, 80 bytes/plane, 80 bytes/line, 400 lines }
        begin
          DestOff := 34 + LongInt(Line) * 80;
          for K := 0 to 79 do
          begin
            SegSetByte(OutBuf, DestOff + K, TempScanline[0, K]);
          end;
        end;
    end;
  end;

  DecompressDegasPC := True;
end;

function DecompressDegasPC1(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
begin
  DecompressDegasPC1 := DecompressDegasPC(InBuf, OutBuf);
end;

type
  PTitByteArray = ^TTitByteArray;
  TTitByteArray = array[0..32767] of Byte;

  TTitHuffNode = record
    Left, Right: Integer;
  end;
  PTitTreeArray = ^TTitTreeArray;
  TTitTreeArray = array[0..511] of TTitHuffNode;

  TLZWPrefix = array[0..4095] of Integer;
  TLZWSuffix = array[0..4095] of Byte;
  TLZWStack  = array[0..4095] of Byte;
  PLZWPrefix = ^TLZWPrefix;
  PLZWSuffix = ^TLZWSuffix;
  PLZWStack  = ^TLZWStack;

  TTitCtrlArray = array[0..3999] of Byte;
  PTitCtrlArray = ^TTitCtrlArray;

function DecompressTitusPC1(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
var
  Method: Word;
  UncompressedSize: LongInt;
  Pos: LongInt;
  TreeSize: Integer;
  Tree: PTitTreeArray;
  BitBuf: Byte;
  BitCnt: Integer;
  Node: Integer;
  Val: Integer;
  StreamBuf: PTitByteArray;
  StreamLen: LongInt;

  NextCode, NBits, MaxCode: Integer;
  ForceReload: Boolean;
  LZWBlock: array[0..15] of Byte;
  LZWBlockLen: Integer;
  LZWBitOff, LZWBitLim: Integer;
  Prefix: PLZWPrefix;
  Suffix: PLZWSuffix;
  Stack:  PLZWStack;
  StackPtr: Integer;
  Code, OldCode, InCode: Integer;
  FinChar: Byte;
  D6, D5, ByteIdx, BitIdx: Integer;
  D0Val, D7Val, D0Len, D6Shift, D1Val: Integer;
  I: Integer;

  SPos: LongInt;
  Red, Green, Blue: array[0..15] of Byte;
  Ctrl: PTitCtrlArray;
  CtrlLen: Integer;
  B, Cnt, Rep, D3, D0: Byte;
  Plane, Col, Block, Bit: Integer;
  Addr: LongInt;
  PalWord: Word;
  R, G, Bl: Word;

  function LZWReadCode: Integer;
  var J: Integer;
  begin
    if ForceReload or (LZWBitOff >= LZWBitLim) or (NextCode > MaxCode) then
    begin
      if NextCode > MaxCode then
      begin
        Inc(NBits);
        if NBits = 12 then
          MaxCode := 4096
        else
          MaxCode := (1 shl NBits) - 1;
      end;
      ForceReload := False;
      LZWBlockLen := 0;
      for J := 0 to NBits - 1 do
      begin
        if Pos < InBuf.TotalSize then
        begin
          LZWBlock[LZWBlockLen] := SegGetByte(InBuf, Pos);
          Inc(Pos);
          Inc(LZWBlockLen);
        end
        else
          Break;
      end;
      if LZWBlockLen = 0 then begin LZWReadCode := -1; Exit; end;
      LZWBitOff := 0;
      LZWBitLim := LZWBlockLen * 8 - (NBits - 1);
    end;

    D6 := LZWBitOff;
    D5 := NBits;
    ByteIdx := D6 shr 3;
    BitIdx := D6 and 7;
    if ByteIdx >= LZWBlockLen then begin LZWReadCode := -1; Exit; end;

    D0Val := LZWBlock[ByteIdx];
    Inc(ByteIdx);
    D7Val := D0Val shr BitIdx;
    D0Len := 8 - BitIdx;
    Dec(D5, D0Len);
    D6Shift := D0Len;

    if D5 >= 8 then
    begin
      if ByteIdx < LZWBlockLen then
      begin
        D1Val := LZWBlock[ByteIdx];
        Inc(ByteIdx);
        D7Val := D7Val or (D1Val shl D6Shift);
        Inc(D6Shift, 8);
        Dec(D5, 8);
      end;
    end;

    if D5 > 0 then
    begin
      if ByteIdx < LZWBlockLen then
      begin
        D1Val := LZWBlock[ByteIdx];
        D7Val := D7Val or ((D1Val and ((1 shl D5) - 1)) shl D6Shift);
      end;
    end;

    Inc(LZWBitOff, NBits);
    LZWReadCode := D7Val;
  end;

  function NextBit: Integer;
  begin
    if BitCnt >= 8 then
    begin
      if Pos < InBuf.TotalSize then
      begin
        BitBuf := SegGetByte(InBuf, Pos);
        Inc(Pos);
      end
      else
        BitBuf := 0;
      BitCnt := 0;
    end;
    NextBit := (BitBuf shr BitCnt) and 1;
    Inc(BitCnt);
  end;

begin
  DecompressTitusPC1 := False;
  if InBuf.TotalSize < 12 then Exit;

  Method := Word(SegGetByte(InBuf, 0)) or (Word(SegGetByte(InBuf, 1)) shl 8);
  UncompressedSize := LongInt(SegGetByte(InBuf, 2)) or
                      (LongInt(SegGetByte(InBuf, 3)) shl 8) or
                      (LongInt(SegGetByte(InBuf, 4)) shl 16) or
                      (LongInt(SegGetByte(InBuf, 5)) shl 24);

  if (Method <> 1) and (Method <> 2) then Exit;
  if (UncompressedSize <= 0) or (UncompressedSize > 65000) then Exit;

  GetMem(StreamBuf, UncompressedSize);
  Pos := 6;

  if Method = 1 then
  begin
    { Huffman }
    Pos := 10;
    while (Pos < InBuf.TotalSize) and (SegGetByte(InBuf, Pos) <> 0) do Inc(Pos);
    Inc(Pos);
    if Pos + 2 > InBuf.TotalSize then begin FreeMem(StreamBuf, UncompressedSize); Exit; end;

    TreeSize := Integer(Word(SegGetByte(InBuf, Pos)) or (Word(SegGetByte(InBuf, Pos + 1)) shl 8));
    Inc(Pos, 2);
    if (TreeSize <= 0) or (Pos + LongInt(TreeSize) * 4 > InBuf.TotalSize) then
    begin
      FreeMem(StreamBuf, UncompressedSize);
      Exit;
    end;

    GetMem(Tree, TreeSize * SizeOf(TTitHuffNode));
    for I := 0 to TreeSize - 1 do
    begin
      Tree^[I].Left := Integer(Word(SegGetByte(InBuf, Pos)) or (Word(SegGetByte(InBuf, Pos + 1)) shl 8));
      Tree^[I].Right := Integer(Word(SegGetByte(InBuf, Pos + 2)) or (Word(SegGetByte(InBuf, Pos + 3)) shl 8));
      Inc(Pos, 4);
    end;

    BitBuf := 0;
    BitCnt := 8;
    StreamLen := 0;
    while (StreamLen < UncompressedSize) and (Pos <= InBuf.TotalSize) do
    begin
      Node := 0;
      while Node >= 0 do
      begin
        if NextBit = 0 then
          Node := Tree^[Node].Left
        else
          Node := Tree^[Node].Right;
      end;
      Val := -(Node + 1);
      if Val = 256 then Break;
      StreamBuf^[StreamLen] := Byte(Val and $FF);
      Inc(StreamLen);
    end;
    FreeMem(Tree, TreeSize * SizeOf(TTitHuffNode));
  end
  else
  begin
    { Method 2: Titus LZW }
    New(Prefix);
    New(Suffix);
    New(Stack);

    Pos := 7;
    NextCode := $101;
    NBits := 9;
    MaxCode := 511;
    ForceReload := False;
    LZWBitOff := 0;
    LZWBitLim := 0;
    StackPtr := 0;
    StreamLen := 0;

    for I := 0 to 255 do
      Suffix^[I] := Byte(I);
    FillChar(Prefix^, SizeOf(TLZWPrefix), 0);

    Code := LZWReadCode;
    if Code = -1 then
    begin
      Dispose(Stack); Dispose(Suffix); Dispose(Prefix);
      FreeMem(StreamBuf, UncompressedSize);
      Exit;
    end;

    FinChar := Byte(Code and $FF);
    OldCode := FinChar;
    StreamBuf^[StreamLen] := FinChar;
    Inc(StreamLen);

    while StreamLen < UncompressedSize do
    begin
      Code := LZWReadCode;
      if Code = -1 then Break;

      if Code = $100 then
      begin
        NextCode := $100;
        ForceReload := True;
        NBits := 9;
        MaxCode := 511;
        Code := LZWReadCode;
        if Code = -1 then Break;
      end;

      InCode := Code;
      if Code >= NextCode then
      begin
        Stack^[StackPtr] := FinChar;
        Inc(StackPtr);
        Code := OldCode;
      end;

      while Code >= $100 do
      begin
        Stack^[StackPtr] := Suffix^[Code];
        Inc(StackPtr);
        Code := Prefix^[Code];
      end;

      FinChar := Byte(Suffix^[Code] and $FF);
      Stack^[StackPtr] := FinChar;
      Inc(StackPtr);

      while (StackPtr > 0) and (StreamLen < UncompressedSize) do
      begin
        Dec(StackPtr);
        StreamBuf^[StreamLen] := Stack^[StackPtr];
        Inc(StreamLen);
      end;

      if NextCode < 4096 then
      begin
        Prefix^[NextCode] := OldCode;
        Suffix^[NextCode] := FinChar;
        Inc(NextCode);
      end;

      OldCode := InCode;
    end;

    Dispose(Stack);
    Dispose(Suffix);
    Dispose(Prefix);
  end;

  if StreamLen < 48 + 4 then
  begin
    FreeMem(StreamBuf, UncompressedSize);
    Exit;
  end;

  SPos := 0;
  for I := 0 to 15 do
  begin
    Red[I] := StreamBuf^[SPos]; Inc(SPos);
  end;
  for I := 0 to 15 do
  begin
    Green[I] := StreamBuf^[SPos]; Inc(SPos);
  end;
  for I := 0 to 15 do
  begin
    Blue[I] := StreamBuf^[SPos]; Inc(SPos);
  end;
  Inc(SPos, 4);

  GetMem(Ctrl, 4000);
  CtrlLen := 0;
  while (CtrlLen < 4000) and (SPos < StreamLen) do
  begin
    B := StreamBuf^[SPos]; Inc(SPos);
    if B = $80 then Continue;
    if B < $80 then
    begin
      Cnt := B + 1;
      while (Cnt > 0) and (SPos < StreamLen) and (CtrlLen < 4000) do
      begin
        Ctrl^[CtrlLen] := StreamBuf^[SPos]; Inc(SPos);
        Inc(CtrlLen);
        Dec(Cnt);
      end;
    end
    else
    begin
      Cnt := (256 - B) + 1;
      if SPos < StreamLen then
      begin
        Rep := StreamBuf^[SPos]; Inc(SPos);
        while (Cnt > 0) and (CtrlLen < 4000) do
        begin
          Ctrl^[CtrlLen] := Rep;
          Inc(CtrlLen);
          Dec(Cnt);
        end;
      end;
    end;
  end;
  Inc(SPos, 4);

  if CtrlLen < 4000 then
  begin
    FreeMem(Ctrl, 4000);
    FreeMem(StreamBuf, UncompressedSize);
    Exit;
  end;

  if not SegAllocate(OutBuf, 32034) then
  begin
    FreeMem(Ctrl, 4000);
    FreeMem(StreamBuf, UncompressedSize);
    Exit;
  end;

  { Write DEGAS .PI1 format: 2 bytes res, 32 bytes pal, 32000 bytes screen }
  SegSetByte(OutBuf, 0, 0);
  SegSetByte(OutBuf, 1, 0);
  for I := 0 to 15 do
  begin
    R := (Red[I] shr 5) and 7;
    G := (Green[I] shr 5) and 7;
    Bl := (Blue[I] shr 5) and 7;
    PalWord := (R shl 8) or (G shl 4) or Bl;
    SegSetByte(OutBuf, 2 + I * 2, Byte((PalWord shr 8) and $FF));
    SegSetByte(OutBuf, 2 + I * 2 + 1, Byte(PalWord and $FF));
  end;

  { Initialize 32000 screen bytes to 0 }
  for Addr := 34 to 32033 do
    SegSetByte(OutBuf, Addr, 0);

  CtrlLen := 0; { Use as CIdx }
  D0 := 0;

  for Plane := 0 to 3 do
    for Col := 0 to 19 do
    begin
      for Block := 0 to 24 do
      begin
        D3 := Ctrl^[CtrlLen]; Inc(CtrlLen);
        for Bit := 0 to 7 do
        begin
          Addr := 34 + LongInt(Block * 8 + Bit) * 160 + Col * 8 + Plane * 2;
          if ((D3 shr Bit) and 1) = 0 then
          begin
            if SPos < StreamLen then
            begin
              D0 := StreamBuf^[SPos]; Inc(SPos);
            end;
          end;
          SegSetByte(OutBuf, Addr, D0);
        end;
      end;

      for Block := 0 to 24 do
      begin
        D3 := Ctrl^[CtrlLen]; Inc(CtrlLen);
        for Bit := 0 to 7 do
        begin
          Addr := 34 + LongInt(Block * 8 + Bit) * 160 + Col * 8 + Plane * 2 + 1;
          if ((D3 shr Bit) and 1) = 0 then
          begin
            if SPos < StreamLen then
            begin
              D0 := StreamBuf^[SPos]; Inc(SPos);
            end;
          end;
          SegSetByte(OutBuf, Addr, D0);
        end;
      end;
    end;

  FreeMem(Ctrl, 4000);
  FreeMem(StreamBuf, UncompressedSize);
  DecompressTitusPC1 := True;
end;

{ =============================================================================
  FIRE Packer / Pack-Fire Decompressor
  ============================================================================= }

function DecompressFire(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
var
  InPos, OutPos, PayloadStart, PayloadEnd: LongInt;
  UnpackedSize, PackedSize: LongInt;
  BitBuf, Extend: Byte;
  HeaderFound: Boolean;
  Off: LongInt;
  Bit1, Bit2: Byte;
  LitCount, Val: LongInt;
  I: LongInt;
  Mode, SubMode: LongInt;
  Dist, LengthVal: LongInt;
  LastByte: Byte;
  Shift: LongInt;

  function FireGetBit: Byte;
  var
    NewByte: Byte;
  begin
    FireGetBit := (BitBuf shr 7) and 1;
    BitBuf := (BitBuf shl 1) and $FF;
    Extend := FireGetBit;
    if BitBuf = 0 then
    begin
      if InPos <= PayloadStart then
      begin
        FireGetBit := 0;
        Exit;
      end;
      Dec(InPos);
      NewByte := SegGetByte(InBuf, InPos);
      FireGetBit := (NewByte shr 7) and 1;
      BitBuf := ((NewByte shl 1) or Extend) and $FF;
      Extend := FireGetBit;
    end;
  end;

  function FireReadBits(Count: Integer): LongInt;
  var
    ResVal: LongInt;
    J: Integer;
  begin
    ResVal := 0;
    for J := 1 to Count do
      ResVal := (ResVal shl 1) or FireGetBit;
    FireReadBits := ResVal;
  end;

  function FireReadDistance: LongInt;
  var
    Idx: LongInt;
  begin
    Idx := FireReadBits(2);
    case Idx of
      0: FireReadDistance := FireReadBits(4);
      1: FireReadDistance := FireReadBits(8) + 16;
      2: FireReadDistance := FireReadBits(12) + 272;
    else
      FireReadDistance := FireReadBits(16) + 4368;
    end;
  end;

  function FireReadOptDistance(var DistVal: LongInt): Boolean;
  var
    Idx: LongInt;
  begin
    Idx := FireReadBits(2);
    if Idx = 0 then
    begin
      DistVal := 0;
      FireReadOptDistance := False;
      Exit;
    end;
    Dec(Idx);
    case Idx of
      0: DistVal := FireReadBits(4);
      1: DistVal := FireReadBits(8) + 16;
    else
      DistVal := FireReadBits(12) + 272;
    end;
    FireReadOptDistance := True;
  end;

  procedure FireCopyMatch(Len: Integer; DistVal: LongInt);
  var
    OffsetVal: LongInt;
    K: Integer;
  begin
    OffsetVal := DistVal + LongInt(Len);
    for K := 1 to Len do
    begin
      if (OutPos <= 0) or (OutPos + OffsetVal > UnpackedSize) then
        Exit;
      Dec(OutPos);
      SegSetByte(OutBuf, OutPos, SegGetByte(OutBuf, OutPos + OffsetVal));
    end;
  end;

  function IsPackFireAxe: Boolean;
  var
    OffCheck: LongInt;
  begin
    IsPackFireAxe := False;
    if (InBuf.TotalSize < 70) or (SegGetByte(InBuf, 0) <> $60) or (SegGetByte(InBuf, 1) <> $1A) then Exit;
    if SegReadWordBE(InBuf, 60) <> $DBFC then Exit;
    for OffCheck := 20 to 60 do
    begin
      if SegCheckString(InBuf, OffCheck, 'Pack-Fire') or SegCheckString(InBuf, OffCheck, 'Axe/Delight') then
      begin
        IsPackFireAxe := True;
        Exit;
      end;
    end;
  end;

  function DecompressPackFireAxe: Boolean;
  var
    ImmOffset, TrailerPos: LongInt;
    A5, OutPos: LongInt;
    BitBuf, RawSize: LongInt;
    Bit, Bit2, BitSub, BitSub2: Byte;
    LitCount, D1: LongInt;
    Mode, SubMode, Dist, MatchLen, Shift: LongInt;
    LastB: Byte;
    K, VIdx: Integer;
  const
    VlcCmp: array[0..3] of Word = (3, 3, 7, $3FF);
    VlcBits: array[0..3] of Byte = (2, 2, 3, 10);
    VlcAdd: array[0..3] of Byte = (1, 4, 7, 14);

    function GetBit32: Byte;
    var W32: LongInt;
    begin
      if BitBuf < 0 then GetBit32 := 1 else GetBit32 := 0;
      BitBuf := BitBuf shl 1;
      if BitBuf = 0 then
      begin
        if A5 < 4 then begin GetBit32 := 0; Exit; end;
        Dec(A5, 4);
        W32 := SegReadLongBE(InBuf, A5);
        if W32 < 0 then GetBit32 := 1 else GetBit32 := 0;
        BitBuf := (W32 shl 1) or 1;
      end;
    end;

    function ReadBits32(Count: Integer): LongInt;
    var ResVal: LongInt; J: Integer;
    begin
      ResVal := 0;
      for J := 1 to Count do ResVal := (ResVal shl 1) or GetBit32;
      ReadBits32 := ResVal;
    end;

    function ReadDistance32: LongInt;
    var Idx: LongInt;
    begin
      Idx := ReadBits32(2);
      case Idx of
        0: ReadDistance32 := ReadBits32(4);
        1: ReadDistance32 := ReadBits32(8) + 16;
        2: ReadDistance32 := ReadBits32(12) + 272;
      else
        ReadDistance32 := ReadBits32(16) + 4368;
      end;
    end;

    function ReadOptDistance32(var ADist: LongInt): Boolean;
    var DVal: LongInt;
    begin
      DVal := ReadBits32(2);
      if DVal = 0 then begin ADist := 0; ReadOptDistance32 := False; Exit; end;
      Dec(DVal);
      case DVal of
        0: ADist := ReadBits32(4);
        1: ADist := ReadBits32(8) + 16;
        2: ADist := ReadBits32(12) + 272;
      else
        ADist := ReadBits32(16) + 4368;
      end;
      ReadOptDistance32 := True;
    end;

    procedure CopyMatch32(ALen: Integer; ADist: LongInt);
    var OffsetVal: LongInt; J: Integer;
    begin
      OffsetVal := ADist + LongInt(ALen);
      for J := 1 to ALen do
      begin
        if (OutPos <= 0) or (OutPos + OffsetVal > RawSize) then Exit;
        Dec(OutPos);
        SegSetByte(OutBuf, OutPos, SegGetByte(OutBuf, OutPos + OffsetVal));
      end;
    end;

  begin
    DecompressPackFireAxe := False;
    ImmOffset := SegReadLongBE(InBuf, 62);
    TrailerPos := 28 + ImmOffset;
    if (TrailerPos < 20) or (TrailerPos > InBuf.TotalSize) then Exit;

    A5 := TrailerPos;
    if A5 < 8 then Exit;
    Dec(A5, 4);
    RawSize := SegReadLongBE(InBuf, A5);
    Dec(A5, 4);
    BitBuf := SegReadLongBE(InBuf, A5);

    if (RawSize <= 0) or (RawSize > 524288) then Exit;
    if not SegAllocate(OutBuf, RawSize) then Exit;
    OutPos := RawSize;

    while OutPos > 0 do
    begin
      Bit := GetBit32;
      if Bit = 1 then
      begin
        Bit2 := GetBit32;
        if Bit2 = 0 then
          LitCount := 1
        else
        begin
          LitCount := 1;
          for VIdx := 0 to 3 do
          begin
            D1 := ReadBits32(VlcBits[VIdx]);
            if (D1 <> VlcCmp[VIdx]) or (VlcCmp[VIdx] = $3FF) then
            begin
              LitCount := D1 + VlcAdd[VIdx] + 1;
              Break;
            end;
          end;
        end;

        for K := 1 to LitCount do
        begin
          if (A5 <= 0) or (OutPos <= 0) then Exit;
          Dec(A5);
          Dec(OutPos);
          SegSetByte(OutBuf, OutPos, SegGetByte(InBuf, A5));
        end;
      end;

      if OutPos <= 0 then Break;

      Mode := ReadBits32(2);
      case Mode of
        0:
        begin
          SubMode := ReadBits32(2);
          if SubMode = 0 then
          begin
            Dist := ReadDistance32;
            if Dist > 0 then
            begin
              if OutPos >= RawSize then Exit;
              LastB := SegGetByte(OutBuf, OutPos);
              for K := 0 to Dist do
              begin
                if OutPos <= 0 then Exit;
                Dec(OutPos);
                SegSetByte(OutBuf, OutPos, LastB);
              end;
            end;
          end
          else
          begin
            case SubMode of
              1: MatchLen := ReadBits32(4) + 5;
              2: MatchLen := ReadBits32(6) + 21;
            else
              MatchLen := ReadBits32(8) + 85;
            end;
            Dist := ReadDistance32;
            CopyMatch32(MatchLen, Dist);
          end;
        end;

        1:
        begin
          Dist := ReadBits32(8);
          CopyMatch32(2, Dist);
        end;

        2:
        begin
          if not ReadOptDistance32(Dist) then
          begin
            if OutPos <= 0 then Exit;
            Dec(OutPos);
            SegSetByte(OutBuf, OutPos, 0);
          end
          else
            CopyMatch32(3, Dist);
        end;

        3:
        begin
          BitSub := GetBit32;
          if BitSub = 0 then
          begin
            Shift := ReadBits32(3);
            if OutPos <= 0 then Exit;
            Dec(OutPos);
            SegSetByte(OutBuf, OutPos, Byte(1 shl Shift));
          end
          else
          begin
            BitSub2 := GetBit32;
            if BitSub2 = 0 then
            begin
              if not ReadOptDistance32(Dist) then
              begin
                if (OutPos <= 0) or (OutPos >= RawSize) then Exit;
                LastB := SegGetByte(OutBuf, OutPos);
                Dec(OutPos);
                SegSetByte(OutBuf, OutPos, LastB);
              end
              else
                CopyMatch32(4, Dist);
            end
            else
            begin
              if not ReadOptDistance32(Dist) then
              begin
                if OutPos <= 0 then Exit;
                Dec(OutPos);
                SegSetByte(OutBuf, OutPos, $FF);
              end
              else
                CopyMatch32(5, Dist);
            end;
          end;
        end;
      end;
    end;

    DecompressPackFireAxe := (OutPos = 0);
  end;

begin
  DecompressFire := False;
  SegInit(OutBuf);
  if InBuf.TotalSize < 16 then Exit;

  { 0. Check for Pack-Fire by Axe/Delight (trailer-based 32-bit executable) }
  if IsPackFireAxe then
  begin
    if DecompressPackFireAxe then
    begin
      DecompressFire := True;
      Exit;
    end;
  end;

  HeaderFound := False;
  PayloadStart := 0;
  PayloadEnd := 0;
  UnpackedSize := 0;

  if SegCheckString(InBuf, 0, 'FIRE') then
  begin
    PackedSize := SegReadLongBE(InBuf, 4);
    UnpackedSize := SegReadLongBE(InBuf, 8);
    if (PackedSize >= 12) and (UnpackedSize > 0) and (UnpackedSize <= 524288) then
    begin
      PayloadStart := 12;
      PayloadEnd := PackedSize;
      if PayloadEnd > InBuf.TotalSize then PayloadEnd := InBuf.TotalSize;
      HeaderFound := True;
    end;
  end;

  if not HeaderFound then
  begin
    for Off := 0 to InBuf.TotalSize - 16 do
    begin
      if Off > 4096 then Break;
      if SegCheckString(InBuf, Off, 'FIRE') then
      begin
        PackedSize := SegReadLongBE(InBuf, Off + 4);
        UnpackedSize := SegReadLongBE(InBuf, Off + 8);
        if (PackedSize >= 12) and (UnpackedSize > 0) and (UnpackedSize <= 524288) then
        begin
          PayloadStart := Off + 12;
          PayloadEnd := Off + PackedSize;
          if PayloadEnd > InBuf.TotalSize then PayloadEnd := InBuf.TotalSize;
          HeaderFound := True;
          Break;
        end;
      end;
    end;
  end;

  if not HeaderFound then Exit;
  if not SegAllocate(OutBuf, UnpackedSize) then Exit;

  OutPos := UnpackedSize;
  InPos := PayloadEnd;
  Dec(InPos);
  BitBuf := SegGetByte(InBuf, InPos);
  Extend := 0;

  while OutPos > 0 do
  begin
    Bit1 := FireGetBit;
    if Bit1 <> 0 then
    begin
      Bit2 := FireGetBit;
      if Bit2 = 0 then
        LitCount := 1
      else
      begin
        Val := FireReadBits(2);
        if Val <> 3 then
          LitCount := Val + 2
        else
        begin
          Val := FireReadBits(2);
          if Val <> 3 then
            LitCount := Val + 5
          else
          begin
            Val := FireReadBits(3);
            if Val <> 7 then
              LitCount := Val + 8
            else
              LitCount := FireReadBits(10) + 15;
          end;
        end;
      end;

      for I := 1 to LitCount do
      begin
        if (InPos <= PayloadStart) or (OutPos <= 0) then
        begin
          SegFree(OutBuf);
          Exit;
        end;
        Dec(InPos);
        Dec(OutPos);
        SegSetByte(OutBuf, OutPos, SegGetByte(InBuf, InPos));
      end;
    end;

    if OutPos <= 0 then Break;

    Mode := FireReadBits(2);
    case Mode of
      0:
      begin
        SubMode := FireReadBits(2);
        if SubMode = 0 then
        begin
          Dist := FireReadDistance;
          if Dist > 0 then
          begin
            if OutPos >= UnpackedSize then begin SegFree(OutBuf); Exit; end;
            LastByte := SegGetByte(OutBuf, OutPos);
            for I := 0 to Dist do
            begin
              if OutPos <= 0 then begin SegFree(OutBuf); Exit; end;
              Dec(OutPos);
              SegSetByte(OutBuf, OutPos, LastByte);
            end;
          end;
        end
        else
        begin
          case SubMode of
            1: LengthVal := FireReadBits(4) + 5;
            2: LengthVal := FireReadBits(6) + 21;
          else
            LengthVal := FireReadBits(8) + 85;
          end;
          Dist := FireReadDistance;
          FireCopyMatch(LengthVal, Dist);
        end;
      end;

      1:
      begin
        Dist := FireReadBits(8);
        FireCopyMatch(2, Dist);
      end;

      2:
      begin
        if not FireReadOptDistance(Dist) then
        begin
          if OutPos <= 0 then begin SegFree(OutBuf); Exit; end;
          Dec(OutPos);
          SegSetByte(OutBuf, OutPos, 0);
        end
        else
          FireCopyMatch(3, Dist);
      end;

      3:
      begin
        if FireGetBit = 0 then
        begin
          Shift := FireReadBits(3);
          if OutPos <= 0 then begin SegFree(OutBuf); Exit; end;
          Dec(OutPos);
          SegSetByte(OutBuf, OutPos, Byte(1 shl Shift));
        end
        else
        begin
          if FireGetBit = 0 then
          begin
            if not FireReadOptDistance(Dist) then
            begin
              if (OutPos <= 0) or (OutPos >= UnpackedSize) then begin SegFree(OutBuf); Exit; end;
              LastByte := SegGetByte(OutBuf, OutPos);
              Dec(OutPos);
              SegSetByte(OutBuf, OutPos, LastByte);
            end
            else
              FireCopyMatch(4, Dist);
          end
          else
          begin
            if not FireReadOptDistance(Dist) then
            begin
              if OutPos <= 0 then begin SegFree(OutBuf); Exit; end;
              Dec(OutPos);
              SegSetByte(OutBuf, OutPos, $FF);
            end
            else
              FireCopyMatch(5, Dist);
          end;
        end;
      end;
    end;
  end;

  DecompressFire := (OutPos = 0);
end;

{ =============================================================================
  PowerPacker Decompressor (PP20)
  ============================================================================= }

function DecompressPowerPacker(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
var
  DataStart, PPSize, OutLen, OutPos: LongInt;
  SkipBits: Byte;
  BitstreamPos: LongInt;
  BitBuf: LongInt;
  BitBufCount: Integer;
  Tail, TextLen: LongInt;
  N, X, K: LongInt;
  MatchCode, OffBits, MatchLen, OffsetVal: LongInt;
  Eff: array[0..3] of Byte;
  I: Integer;

  function PPReadBits(Count: Integer): LongInt;
  var
    V: LongInt;
    Step: Integer;
  begin
    V := 0;
    for Step := 1 to Count do
    begin
      if BitBufCount = 0 then
      begin
        Dec(BitstreamPos, 4);
        if BitstreamPos < DataStart + 8 then
        begin
          PPReadBits := 0;
          Exit;
        end;
        BitBuf := SegReadLongBE(InBuf, BitstreamPos);
        BitBufCount := 32;
      end;
      V := (V shl 1) or (BitBuf and 1);
      BitBuf := BitBuf shr 1;
      Dec(BitBufCount);
    end;
    PPReadBits := V;
  end;

begin
  DecompressPowerPacker := False;
  SegInit(OutBuf);
  if InBuf.TotalSize < 16 then Exit;

  DataStart := -1;
  if (InBuf.TotalSize >= 28) and (SegReadWordBE(InBuf, 0) = $601A) then
  begin
    TextLen := SegReadLongBE(InBuf, 2);
    if (TextLen > 0) and (28 + TextLen + 16 <= InBuf.TotalSize) then
    begin
      if SegCheckString(InBuf, 28 + TextLen, 'PP20') then
        DataStart := 28 + TextLen;
    end;
  end;

  if (DataStart = -1) and SegCheckString(InBuf, 0, 'PP20') then
    DataStart := 0;

  if DataStart = -1 then
  begin
    for I := 0 to 4096 do
    begin
      if I + 16 > InBuf.TotalSize then Break;
      if SegCheckString(InBuf, I, 'PP20') then
      begin
        DataStart := I;
        Break;
      end;
    end;
  end;

  if DataStart < 0 then Exit;

  PPSize := InBuf.TotalSize - DataStart;
  if PPSize < 16 then Exit;

  Eff[0] := SegGetByte(InBuf, DataStart + 4);
  Eff[1] := SegGetByte(InBuf, DataStart + 5);
  Eff[2] := SegGetByte(InBuf, DataStart + 6);
  Eff[3] := SegGetByte(InBuf, DataStart + 7);

  Tail := SegReadLongBE(InBuf, InBuf.TotalSize - 4);
  OutLen := Tail shr 8;
  SkipBits := Byte(Tail and $FF);

  if (OutLen <= 0) or (OutLen > 524288) or (SkipBits > 32) then Exit;
  if not SegAllocate(OutBuf, OutLen) then Exit;

  OutPos := OutLen;
  BitstreamPos := InBuf.TotalSize - 4;
  BitBuf := 0;
  BitBufCount := 0;

  PPReadBits(SkipBits);

  while OutPos > 0 do
  begin
    if PPReadBits(1) = 0 then
    begin
      N := 1;
      repeat
        X := PPReadBits(2);
        Inc(N, X);
      until X <> 3;

      for K := 1 to N do
      begin
        if OutPos <= 0 then begin SegFree(OutBuf); Exit; end;
        Dec(OutPos);
        SegSetByte(OutBuf, OutPos, Byte(PPReadBits(8)));
      end;
      if OutPos = 0 then Break;
    end;

    MatchCode := PPReadBits(2);
    OffBits := Eff[MatchCode];
    if MatchCode = 3 then
    begin
      if PPReadBits(1) = 0 then
        OffBits := 7;
      OffsetVal := PPReadBits(OffBits);
      MatchLen := 5;
      repeat
        X := PPReadBits(3);
        Inc(MatchLen, X);
      until X <> 7;
    end
    else
    begin
      OffsetVal := PPReadBits(OffBits);
      MatchLen := MatchCode + 2;
    end;

    for K := 1 to MatchLen do
    begin
      if (OutPos <= 0) or (OutPos + OffsetVal >= OutLen) then
      begin
        SegFree(OutBuf);
        Exit;
      end;
      Dec(OutPos);
      SegSetByte(OutBuf, OutPos, SegGetByte(OutBuf, OutPos + OffsetVal + 1));
    end;
  end;

  DecompressPowerPacker := (OutPos = 0);
end;

{ =============================================================================
  Thunder Packer Decompressor (ATOM)
  ============================================================================= }

function DecompressThunder(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
var
  AtomOffset, A2, PackedEnd, A4, Count, LengthVal, OffsetVal, MatchPtr, I: LongInt;
  UncompressedLen, PackedLen: LongInt;
  D4, D1, D2, NextByte, CarryVal: Word;
begin
  DecompressThunder := False;
  SegInit(OutBuf);
  if InBuf.TotalSize < 12 then Exit;

  AtomOffset := -1;
  for I := 0 to 4096 do
  begin
    if I + 12 > InBuf.TotalSize then Break;
    if SegCheckString(InBuf, I, 'ATOM') then
    begin
      AtomOffset := I;
      Break;
    end;
  end;

  if (AtomOffset < 0) or (AtomOffset + 12 > InBuf.TotalSize) then Exit;

  UncompressedLen := SegReadLongBE(InBuf, AtomOffset + 4);
  PackedLen := SegReadLongBE(InBuf, AtomOffset + 8);
  if (UncompressedLen <= 0) or (UncompressedLen > 524288) then Exit;

  A2 := AtomOffset + 12;
  PackedEnd := A2 + PackedLen;
  if PackedEnd > InBuf.TotalSize then PackedEnd := InBuf.TotalSize;

  if not SegAllocate(OutBuf, UncompressedLen) then Exit;
  A4 := 0;
  D1 := 0;

  while (A2 < PackedEnd) and (A4 < UncompressedLen) do
  begin
    if A2 + 1 >= InBuf.TotalSize then Break;
    D4 := SegReadWordBE(InBuf, A2);
    Inc(A2, 2);

    if (D4 and $4000) = 0 then
    begin
      if (D4 and $8000) <> 0 then
      begin
        D4 := D4 and $7FFF;
        if A2 >= InBuf.TotalSize then Break;
        D1 := SegGetByte(InBuf, A2);
        Inc(A2);
      end;
      Inc(D4, $2000);
      while True do
      begin
        CarryVal := D4 and 1;
        D4 := D4 shr 1;
        if D4 = 0 then Break;
        if A4 >= UncompressedLen then Break;
        if CarryVal <> 0 then
        begin
          SegSetByte(OutBuf, A4, Byte(D1));
          Inc(A4);
        end
        else
        begin
          if A2 >= InBuf.TotalSize then Break;
          SegSetByte(OutBuf, A4, SegGetByte(InBuf, A2));
          Inc(A4);
          Inc(A2);
        end;
      end;
    end
    else if (D4 and $8000) = 0 then
    begin
      D4 := D4 and $BFFF;
      if A2 >= InBuf.TotalSize then Break;
      D2 := SegGetByte(InBuf, A2);
      Inc(A2);
      Count := D4 + 1;
      for I := 1 to Count do
      begin
        if A4 >= UncompressedLen then Break;
        SegSetByte(OutBuf, A4, Byte(D2));
        Inc(A4);
      end;
    end
    else
    begin
      D4 := D4 and $3FFF;
      if A2 >= InBuf.TotalSize then Break;
      NextByte := SegGetByte(InBuf, A2);
      Inc(A2);
      LengthVal := (D4 shr 8) + 1;
      OffsetVal := ((D4 and $FF) shl 8) or NextByte;
      MatchPtr := A4 - OffsetVal;
      if MatchPtr < 0 then begin SegFree(OutBuf); Exit; end;

      for I := 1 to LengthVal do
      begin
        if A4 >= UncompressedLen then Break;
        SegSetByte(OutBuf, A4, SegGetByte(OutBuf, MatchPtr));
        Inc(A4);
        Inc(MatchPtr);
      end;
    end;
  end;

  if A4 = UncompressedLen then
    DecompressThunder := True
  else
  begin
    SegFree(OutBuf);
    DecompressThunder := False;
  end;
end;

{ =============================================================================
  STOS Squasher Decompressor (SQSH)
  ============================================================================= }

function DecompressStosSquash(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
var
  Offset, UncompressedSize, Checksum, BitBuf, NextWord: LongInt;
  OutPtr, Count, Dist, Val, Mode, NBits, I: LongInt;

  function StosGetBit: Byte;
  begin
    StosGetBit := BitBuf and 1;
    BitBuf := BitBuf shr 1;
    if BitBuf = 0 then
    begin
      if Offset < 4 then
      begin
        StosGetBit := 0;
        Exit;
      end;
      Dec(Offset, 4);
      NextWord := SegReadLongBE(InBuf, Offset);
      StosGetBit := NextWord and 1;
      BitBuf := (NextWord shr 1) or $80000000;
    end;
  end;

  function StosGetBits(N: Integer): LongInt;
  var
    J: Integer;
    ResVal: LongInt;
  begin
    ResVal := 0;
    for J := 1 to N do
      ResVal := (ResVal shl 1) or StosGetBit;
    StosGetBits := ResVal;
  end;

begin
  DecompressStosSquash := False;
  SegInit(OutBuf);
  if InBuf.TotalSize < 16 then Exit;

  Offset := InBuf.TotalSize;
  Dec(Offset, 4);
  UncompressedSize := SegReadLongBE(InBuf, Offset);
  if (UncompressedSize <= 0) or (UncompressedSize > 524288) then Exit;

  Dec(Offset, 4);
  Checksum := SegReadLongBE(InBuf, Offset);
  Dec(Offset, 4);
  BitBuf := SegReadLongBE(InBuf, Offset);

  if not SegAllocate(OutBuf, UncompressedSize) then Exit;
  OutPtr := UncompressedSize;

  while OutPtr > 0 do
  begin
    if StosGetBit = 0 then
    begin
      if StosGetBit = 1 then
      begin
        Dist := StosGetBits(8);
        for I := 1 to 2 do
        begin
          if OutPtr <= 0 then begin SegFree(OutBuf); Exit; end;
          Dec(OutPtr);
          if (OutPtr + Dist < 0) or (OutPtr + Dist >= UncompressedSize) then
          begin
            SegFree(OutBuf); Exit;
          end;
          SegSetByte(OutBuf, OutPtr, SegGetByte(OutBuf, OutPtr + Dist));
        end;
      end
      else
      begin
        Count := StosGetBits(3);
        for I := 0 to Count do
        begin
          Val := StosGetBits(8);
          if OutPtr <= 0 then begin SegFree(OutBuf); Exit; end;
          Dec(OutPtr);
          SegSetByte(OutBuf, OutPtr, Byte(Val));
        end;
      end;
    end
    else
    begin
      Mode := StosGetBits(2);
      if Mode < 2 then
      begin
        NBits := 9 + Mode;
        Count := Mode + 2;
        Dist := StosGetBits(NBits);
        for I := 0 to Count do
        begin
          if OutPtr <= 0 then begin SegFree(OutBuf); Exit; end;
          Dec(OutPtr);
          if (OutPtr + Dist < 0) or (OutPtr + Dist >= UncompressedSize) then
          begin
            SegFree(OutBuf); Exit;
          end;
          SegSetByte(OutBuf, OutPtr, SegGetByte(OutBuf, OutPtr + Dist));
        end;
      end
      else if Mode = 2 then
      begin
        Count := StosGetBits(8);
        Dist := StosGetBits(12);
        for I := 0 to Count do
        begin
          if OutPtr <= 0 then begin SegFree(OutBuf); Exit; end;
          Dec(OutPtr);
          if (OutPtr + Dist < 0) or (OutPtr + Dist >= UncompressedSize) then
          begin
            SegFree(OutBuf); Exit;
          end;
          SegSetByte(OutBuf, OutPtr, SegGetByte(OutBuf, OutPtr + Dist));
        end;
      end
      else
      begin
        Count := StosGetBits(8) + 8;
        for I := 0 to Count do
        begin
          Val := StosGetBits(8);
          if OutPtr <= 0 then begin SegFree(OutBuf); Exit; end;
          Dec(OutPtr);
          SegSetByte(OutBuf, OutPtr, Byte(Val));
        end;
      end;
    end;
  end;

  DecompressStosSquash := (OutPtr = 0);
end;

{ =============================================================================
  4PAK Executable Decompressor
  ============================================================================= }

function Decompress4PAK(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
var
  Size: LongInt;
  TextLen, DataLen, BssLen: LongInt;
  SrcOffset, SrcPos, OutPos, MatchOffset: LongInt;
  D0, D1, MatchLen, I, B, NextB, PatternPos, P2, P3: LongInt;
  W: Word;
begin
  Decompress4PAK := False;
  SegInit(OutBuf);
  Size := InBuf.TotalSize;
  if Size < 66 then Exit;

  TextLen := 0;
  DataLen := 0;
  BssLen := 0;
  SrcOffset := 0;
  W := SegReadWordBE(InBuf, 0);

  if (Size >= 28) and (W = $601A) then
  begin
    PatternPos := -1;
    for I := Size - 8 downto 28 do
    begin
      if I < Size - 512 then Break;
      if (SegGetByte(InBuf, I) = $22) and (SegGetByte(InBuf, I + 1) = $C0) and
         (SegGetByte(InBuf, I + 2) = $D1) and (SegGetByte(InBuf, I + 3) = $C0) and
         (SegGetByte(InBuf, I + 4) = $22) and (SegGetByte(InBuf, I + 5) = $C8) and
         (SegGetByte(InBuf, I + 6) = $2A) and (SegGetByte(InBuf, I + 7) = $48) then
      begin
        PatternPos := I;
        Break;
      end;
    end;

    if (PatternPos >= 6) and (SegGetByte(InBuf, PatternPos - 6) = $20) and
       (SegGetByte(InBuf, PatternPos - 5) = $3C) then
    begin
      TextLen := SegReadLongBE(InBuf, PatternPos - 4);
      P2 := PatternPos + 8;
      if (P2 + 14 <= Size) and (SegGetByte(InBuf, P2) = $20) and (SegGetByte(InBuf, P2 + 1) = $3C) then
      begin
        DataLen := SegReadLongBE(InBuf, P2 + 2);
        P3 := P2 + 6 + 8;
        if (P3 + 6 <= Size) and (SegGetByte(InBuf, P3) = $20) and (SegGetByte(InBuf, P3 + 1) = $3C) then
          BssLen := SegReadLongBE(InBuf, P3 + 2);
      end;
    end;
    SrcOffset := 66;
  end;

  if not SegAllocate(OutBuf, 524288) then Exit;

  if TextLen > 0 then
    OutPos := 28
  else
    OutPos := 0;

  SrcPos := SrcOffset;

  while SrcPos < Size do
  begin
    B := SegGetByte(InBuf, SrcPos);
    Inc(SrcPos);
    if B = 0 then
      Break
    else if B < 128 then
    begin
      if (SrcPos + B > Size) or (OutPos + B > 524288) then
      begin
        SegFree(OutBuf); Exit;
      end;
      for I := 0 to B - 1 do
      begin
        SegSetByte(OutBuf, OutPos, SegGetByte(InBuf, SrcPos + I));
        Inc(OutPos);
      end;
      Inc(SrcPos, B);
    end
    else
    begin
      D1 := B and $1F;
      if SrcPos >= Size then begin SegFree(OutBuf); Exit; end;
      NextB := SegGetByte(InBuf, SrcPos);
      Inc(SrcPos);
      D0 := ((B shl 3) and $FF00) or NextB;
      MatchOffset := OutPos - $800 + D0;
      MatchLen := D1 + 3;

      if TextLen > 0 then
      begin
        if (MatchOffset < 28) or (MatchOffset >= OutPos) then
        begin
          SegFree(OutBuf); Exit;
        end;
      end
      else
      begin
        if (MatchOffset < 0) or (MatchOffset >= OutPos) then
        begin
          SegFree(OutBuf); Exit;
        end;
      end;

      if OutPos + MatchLen > 524288 then begin SegFree(OutBuf); Exit; end;
      for I := 0 to MatchLen - 1 do
      begin
        SegSetByte(OutBuf, OutPos, SegGetByte(OutBuf, MatchOffset + I));
        Inc(OutPos);
      end;
    end;
  end;

  if (TextLen > 0) and (OutPos <= 28) then begin SegFree(OutBuf); Exit; end;
  if (TextLen = 0) and (OutPos <= 0) then begin SegFree(OutBuf); Exit; end;

  if TextLen > 0 then
  begin
    SegSetByte(OutBuf, 0, $60);
    SegSetByte(OutBuf, 1, $1A);
    SegSetByte(OutBuf, 2, Byte((TextLen shr 24) and $FF));
    SegSetByte(OutBuf, 3, Byte((TextLen shr 16) and $FF));
    SegSetByte(OutBuf, 4, Byte((TextLen shr 8) and $FF));
    SegSetByte(OutBuf, 5, Byte(TextLen and $FF));
    SegSetByte(OutBuf, 6, Byte((DataLen shr 24) and $FF));
    SegSetByte(OutBuf, 7, Byte((DataLen shr 16) and $FF));
    SegSetByte(OutBuf, 8, Byte((DataLen shr 8) and $FF));
    SegSetByte(OutBuf, 9, Byte(DataLen and $FF));
    SegSetByte(OutBuf, 10, Byte((BssLen shr 24) and $FF));
    SegSetByte(OutBuf, 11, Byte((BssLen shr 16) and $FF));
    SegSetByte(OutBuf, 12, Byte((BssLen shr 8) and $FF));
    SegSetByte(OutBuf, 13, Byte(BssLen and $FF));
    for I := 14 to 27 do SegSetByte(OutBuf, I, 0);
  end;

  OutBuf.TotalSize := OutPos;
  Decompress4PAK := True;
end;

{ =============================================================================
  Sentry Packer Decompressor (v2.05 / v2.11 Raw & Executable)
  ============================================================================= }

function DecompressSentry(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
const
  Table1CA_Bits: array[0..3] of Byte = (4, 7, 8, 12);
  Table1CA_Base: array[0..3] of LongInt = (1, $21, $121, $321);
  Table1D6_Bits: array[0..3] of Byte = (1, 2, 4, 8);
  Table1D6_Base: array[0..3] of LongInt = (6, 10, 18, 50);
  Table1E2_Bits: array[0..3] of Byte = (3, 4, 6, 8);
  Table1E2_Base: array[0..3] of LongInt = (1, $11, $31, $B1);
  Table1EE_Base: array[0..3] of LongInt = (2, 5, 12, 27);
  Table1EE_Bits: array[0..3] of Byte = (1, 2, 3, 4);
var
  Size, UncompressedLen: LongInt;
  InPos, OutPos: LongInt;
  BitBuf: LongInt;
  D3, OffsetVal, CountVal, SubVal: LongInt;
  I, MoveIdx: LongInt;
  Bit, Bit2, Bit3: Byte;
  W: Word;

  function SntRefill4: Boolean;
  var K: Integer;
  begin
    if InPos < 4 then begin SntRefill4 := False; Exit; end;
    BitBuf := 0;
    for K := 0 to 3 do
    begin
      Dec(InPos);
      BitBuf := (BitBuf shl 8) or LongInt(SegGetByte(InBuf, InPos));
    end;
    SntRefill4 := True;
  end;

  function SntGetBit: Byte;
  var Carry: Byte;
  begin
    if BitBuf < 0 then Carry := 1 else Carry := 0;
    BitBuf := BitBuf shl 1;
    if BitBuf <> 0 then
    begin
      SntGetBit := Carry;
      Exit;
    end;
    if not SntRefill4 then
    begin
      SntGetBit := 0;
      Exit;
    end;
    if BitBuf < 0 then Carry := 1 else Carry := 0;
    BitBuf := (BitBuf shl 1) or 1;
    SntGetBit := Carry;
  end;

  function SntReadBits(Count: Integer): LongInt;
  var K: Integer; Res: LongInt;
  begin
    Res := 0;
    for K := 1 to Count do
      Res := (Res shl 1) or LongInt(SntGetBit);
    SntReadBits := Res;
  end;

  function SntSub140(const BitsTable: array of Byte; const BaseTable: array of LongInt): LongInt;
  var SubIdx: LongInt;
  begin
    SubIdx := SntReadBits(2);
    SntSub140 := BaseTable[SubIdx] + SntReadBits(BitsTable[SubIdx] + 1);
  end;

begin
  DecompressSentry := False;
  SegInit(OutBuf);
  Size := InBuf.TotalSize;
  if Size < 32 then Exit;

  UncompressedLen := 0;
  InPos := Size;
  W := SegReadWordBE(InBuf, 0);

  if (Size >= 28) and (W = $601A) then
  begin
    InPos := 28 + SegReadLongBE(InBuf, 2);
    if (InPos > Size) or (InPos <= 28) then
      InPos := Size;

    for MoveIdx := 28 to 512 do
    begin
      if MoveIdx + 8 > Size then Break;
      if (SegGetByte(InBuf, MoveIdx) = $24) and (SegGetByte(InBuf, MoveIdx + 1) = $7C) and
         (SegGetByte(InBuf, MoveIdx + 6) = $2E) and (SegGetByte(InBuf, MoveIdx + 7) = $0A) then
      begin
        UncompressedLen := SegReadLongBE(InBuf, MoveIdx + 2);
        Break;
      end;
    end;

    if (UncompressedLen = 0) and (Size > 262) then
    begin
      if (SegGetByte(InBuf, 256) = $24) and (SegGetByte(InBuf, 257) = $7C) then
        UncompressedLen := SegReadLongBE(InBuf, 258);
    end;
  end;

  if (UncompressedLen = 0) and (Size >= 12) and SegCheckString(InBuf, Size - 4, 'Snt2') then
  begin
    InPos := Size - 4;
    UncompressedLen := SegReadLongBE(InBuf, InPos - 4);
    Dec(InPos, 4);
  end;

  if (UncompressedLen <= 0) or (UncompressedLen > 524288) or (InPos < 4) then Exit;

  if not SegAllocate(OutBuf, UncompressedLen) then Exit;
  if not SntRefill4 then begin SegFree(OutBuf); Exit; end;

  OutPos := UncompressedLen;

  while OutPos > 0 do
  begin
    Bit := SntGetBit;
    if Bit = 0 then
    begin
      Bit2 := SntGetBit;
      if Bit2 = 0 then
      begin
        if InPos <= 0 then begin SegFree(OutBuf); Exit; end;
        Dec(InPos);
        Dec(OutPos);
        SegSetByte(OutBuf, OutPos, SegGetByte(InBuf, InPos));
      end
      else
      begin
        Bit3 := SntGetBit;
        if Bit3 = 0 then
          CountVal := 2
        else
        begin
          CountVal := 0;
          for I := 0 to 3 do
          begin
            SubVal := SntReadBits(Table1EE_Bits[I] + 1);
            if SubVal > 0 then
            begin
              CountVal := (SubVal - 1) + Table1EE_Base[I] + 1;
              Break;
            end;
          end;
          if CountVal = 0 then begin SegFree(OutBuf); Exit; end;
        end;

        if (CountVal = 0) or (OutPos < CountVal) or (InPos < CountVal) then
        begin
          SegFree(OutBuf); Exit;
        end;

        for I := 1 to CountVal do
        begin
          Dec(InPos);
          Dec(OutPos);
          SegSetByte(OutBuf, OutPos, SegGetByte(InBuf, InPos));
        end;
      end;
    end
    else
    begin
      Bit2 := SntGetBit;
      if Bit2 = 0 then
      begin
        D3 := 1;
        OffsetVal := SntReadBits(8);
      end
      else
      begin
        Bit3 := SntGetBit;
        if Bit3 = 0 then
        begin
          D3 := 2;
          OffsetVal := SntSub140(Table1E2_Bits, Table1E2_Base);
        end
        else
        begin
          SubVal := SntReadBits(2);
          if SubVal > 0 then
          begin
            D3 := 2 + SubVal;
            OffsetVal := SntSub140(Table1E2_Bits, Table1E2_Base);
          end
          else
          begin
            D3 := SntSub140(Table1D6_Bits, Table1D6_Base);
            OffsetVal := SntSub140(Table1CA_Bits, Table1CA_Base);
          end;
        end;
      end;

      if (OffsetVal = 0) or (OutPos + OffsetVal - 1 >= UncompressedLen) then
      begin
        SegFree(OutBuf); Exit;
      end;

      for I := 0 to D3 do
      begin
        if OutPos <= 0 then begin SegFree(OutBuf); Exit; end;
        Dec(OutPos);
        SegSetByte(OutBuf, OutPos, SegGetByte(OutBuf, OutPos + OffsetVal));
      end;
    end;
  end;

  DecompressSentry := (OutPos = 0);
end;

{ =============================================================================
  STAD Monochrome Image Decompressor (.PAC)
  ============================================================================= }

function DecompressStad(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
var
  Size: LongInt;
  IsVert: Boolean;
  IdByte, PackByte, SpecialByte, CurrByte, RunVal: Byte;
  RunCount: Word;
  InIdx, OutIdx, X, Y: LongInt;
  RawBuf: PBlock32K;
begin
  DecompressStad := False;
  SegInit(OutBuf);
  Size := InBuf.TotalSize;
  if Size < 7 then Exit;

  if SegCheckString(InBuf, 0, 'pM85') then
    IsVert := False
  else if SegCheckString(InBuf, 0, 'pM86') then
    IsVert := True
  else
    Exit;

  IdByte := SegGetByte(InBuf, 4);
  PackByte := SegGetByte(InBuf, 5);
  SpecialByte := SegGetByte(InBuf, 6);

  if MaxAvail < 32768 then Exit;
  GetMem(RawBuf, 32768);
  FillChar(RawBuf^, 32000, 0);

  InIdx := 7;
  OutIdx := 0;

  while (InIdx < Size) and (OutIdx < 32000) do
  begin
    CurrByte := SegGetByte(InBuf, InIdx);
    Inc(InIdx);

    if CurrByte = IdByte then
    begin
      if InIdx >= Size then Break;
      RunCount := Word(SegGetByte(InBuf, InIdx)) + 1;
      Inc(InIdx);
      while (RunCount > 0) and (OutIdx < 32000) do
      begin
        RawBuf^[OutIdx] := PackByte;
        Inc(OutIdx);
        Dec(RunCount);
      end;
    end
    else if CurrByte = SpecialByte then
    begin
      if InIdx + 1 >= Size then Break;
      RunVal := SegGetByte(InBuf, InIdx);
      Inc(InIdx);
      RunCount := SegGetByte(InBuf, InIdx);
      Inc(InIdx);
      while (RunCount > 0) and (OutIdx < 32000) do
      begin
        RawBuf^[OutIdx] := RunVal;
        Inc(OutIdx);
        Dec(RunCount);
      end;
    end
    else
    begin
      RawBuf^[OutIdx] := CurrByte;
      Inc(OutIdx);
    end;
  end;

  if not SegAllocate(OutBuf, 32000) then
  begin
    FreeMem(RawBuf, 32768);
    Exit;
  end;

  if IsVert then
  begin
    for X := 0 to 79 do
      for Y := 0 to 399 do
        SegSetByte(OutBuf, Y * 80 + X, RawBuf^[X * 400 + Y]);
  end
  else
  begin
    for OutIdx := 0 to 31999 do
      SegSetByte(OutBuf, OutIdx, RawBuf^[OutIdx]);
  end;

  FreeMem(RawBuf, 32768);
  DecompressStad := True;
end;

{ =============================================================================
  Happy Packer (EASY / HAPPY)
  ============================================================================= }

type
  THappyNode = record
    Left: Integer;
    Right: Integer;
    Symbol: Byte;
    IsLeaf: Boolean;
  end;

function DecompressHappy(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
var
  InSize, TextLen, Pass1Len, UncompressedLen: LongInt;
  PStore, PEsc, PTree, Disp, TargetPos, TargetEsc, TreeStart, DataSegPos: LongInt;
  Esc1, Esc2, Esc3, Esc2Fill: Byte;
  TreeBytePos, TreeBitPos, DataBytePos, DataBitPos: LongInt;
  TreeNodes: array[0..511] of THappyNode;
  NodeCount: Integer;
  Pass1Buf: TSegBuffer;
  Pass1Pos, Pass2Pos, P: LongInt;
  MaxScan, I, J, K: LongInt;
  B, Val, Cnt, ChunkLen, RepeatCnt: Byte;
  CurrNode: Integer;

  function ReadTreeBit: Byte;
  var CurByte: Byte;
  begin
    if TreeBytePos >= InSize then begin ReadTreeBit := 0; Exit; end;
    CurByte := SegGetByte(InBuf, TreeBytePos);
    ReadTreeBit := (CurByte shr TreeBitPos) and 1;
    Dec(TreeBitPos);
    if TreeBitPos < 0 then
    begin
      TreeBitPos := 7;
      Inc(TreeBytePos);
    end;
  end;

  function BuildNode: Integer;
  var Idx, BitK, LChild, RChild: Integer; Sym: Word;
  begin
    if NodeCount >= 512 then begin BuildNode := -1; Exit; end;
    Idx := NodeCount;
    Inc(NodeCount);
    if ReadTreeBit = 1 then
    begin
      TreeNodes[Idx].IsLeaf := False;
      LChild := BuildNode;
      RChild := BuildNode;
      TreeNodes[Idx].Left := LChild;
      TreeNodes[Idx].Right := RChild;
    end
    else
    begin
      TreeNodes[Idx].IsLeaf := True;
      TreeNodes[Idx].Left := -1;
      TreeNodes[Idx].Right := -1;
      Sym := 0;
      for BitK := 7 downto 0 do
        if ReadTreeBit = 1 then
          Sym := Sym or (1 shl BitK);
      TreeNodes[Idx].Symbol := Byte(Sym and $FF);
    end;
    BuildNode := Idx;
  end;

  function ReadDataBit: Byte;
  var CurByte: Byte;
  begin
    if DataBytePos >= InSize then begin ReadDataBit := 0; Exit; end;
    CurByte := SegGetByte(InBuf, DataBytePos);
    ReadDataBit := (CurByte shr DataBitPos) and 1;
    Dec(DataBitPos);
    if DataBitPos < 0 then
    begin
      DataBitPos := 7;
      Inc(DataBytePos);
    end;
  end;

begin
  DecompressHappy := False;
  InSize := InBuf.TotalSize;
  if (InSize < 28) or (SegReadWordBE(InBuf, 0) <> $601A) then Exit;

  TextLen := SegReadLongBE(InBuf, 2);
  if TextLen + 28 > InSize then Exit;

  Pass1Len := 0;
  UncompressedLen := 0;

  PStore := -1;
  MaxScan := InSize - 4;
  if MaxScan > 2048 then MaxScan := 2048;
  for I := 28 to MaxScan do
  begin
    if (SegGetByte(InBuf, I) = $21) and (SegGetByte(InBuf, I + 1) = $56) and
       (SegGetByte(InBuf, I + 2) = $00) and (SegGetByte(InBuf, I + 3) = $14) then
    begin
      PStore := I;
      Break;
    end;
  end;

  if PStore >= 4 then
  begin
    Disp := Integer(SegReadWordBE(InBuf, PStore - 2));
    if Disp >= $8000 then Disp := Disp - $10000;
    TargetPos := (PStore - 4) + 2 + Disp;
    if (TargetPos >= 4) and (TargetPos + 4 <= InSize) then
    begin
      Pass1Len := SegReadLongBE(InBuf, TargetPos);
      UncompressedLen := SegReadLongBE(InBuf, TargetPos - 4);
    end;
  end;

  if (Pass1Len = 0) and (InSize >= 28 + $582) then
  begin
    Pass1Len := SegReadLongBE(InBuf, 28 + $57E);
    UncompressedLen := SegReadLongBE(InBuf, 28 + $57A);
  end;

  if (Pass1Len <= 0) or (Pass1Len > 524288) or
     (UncompressedLen <= 0) or (UncompressedLen > 524288) then Exit;

  Esc1 := $5B; Esc2 := $5D; Esc3 := $97; Esc2Fill := $00;
  PEsc := -1;
  MaxScan := InSize - 6;
  if MaxScan > 1024 then MaxScan := 1024;
  for I := 28 to MaxScan do
  begin
    if (SegGetByte(InBuf, I) = $10) and (SegGetByte(InBuf, I + 1) = $13) and
       (SegGetByte(InBuf, I + 2) = $B0) and (SegGetByte(InBuf, I + 3) = $2A) and
       (SegGetByte(InBuf, I + 4) = $00) and (SegGetByte(InBuf, I + 5) = $01) then
    begin
      PEsc := I;
      Break;
    end;
  end;

  if PEsc >= 4 then
  begin
    Disp := Integer(SegReadWordBE(InBuf, PEsc - 2));
    if Disp >= $8000 then Disp := Disp - $10000;
    TargetEsc := (PEsc - 4) + 2 + Disp;
    if (TargetEsc >= 0) and (TargetEsc + 8 <= InSize) then
    begin
      Esc1 := SegGetByte(InBuf, TargetEsc + 1);
      Esc2 := SegGetByte(InBuf, TargetEsc + 3);
      Esc3 := SegGetByte(InBuf, TargetEsc + 5);
      Esc2Fill := SegGetByte(InBuf, TargetEsc + 7);
    end;
  end;

  TreeStart := 28 + $594;
  PTree := -1;
  MaxScan := InSize - 6;
  if MaxScan > 2048 then MaxScan := 2048;
  for I := 28 to MaxScan do
  begin
    if (SegGetByte(InBuf, I) = $3F) and (SegGetByte(InBuf, I + 1) = $3C) and
       (SegGetByte(InBuf, I + 2) = $00) and (SegGetByte(InBuf, I + 3) = $00) and
       (SegGetByte(InBuf, I + 4) = $4D) and (SegGetByte(InBuf, I + 5) = $FA) then
    begin
      PTree := I;
      Break;
    end;
  end;

  if PTree >= 4 then
  begin
    Disp := Integer(SegReadWordBE(InBuf, PTree - 2));
    if Disp >= $8000 then Disp := Disp - $10000;
    TargetPos := (PTree - 4) + 2 + Disp;
    if (TargetPos >= 0) and (TargetPos < InSize) then
      TreeStart := TargetPos;
  end;

  NodeCount := 0;
  TreeBytePos := TreeStart;
  TreeBitPos := 7;
  BuildNode;
  if NodeCount = 0 then Exit;

  if not SegAllocate(Pass1Buf, Pass1Len) then Exit;
  DataSegPos := 28 + TextLen;
  DataBytePos := DataSegPos;
  DataBitPos := 7;
  Pass1Pos := 0;

  while Pass1Pos < Pass1Len do
  begin
    CurrNode := 0;
    while not TreeNodes[CurrNode].IsLeaf do
    begin
      if ReadDataBit = 1 then
        CurrNode := TreeNodes[CurrNode].Right
      else
        CurrNode := TreeNodes[CurrNode].Left;
      if (CurrNode < 0) or (CurrNode >= NodeCount) then
      begin
        SegFree(Pass1Buf);
        Exit;
      end;
    end;
    SegSetByte(Pass1Buf, Pass1Pos, TreeNodes[CurrNode].Symbol);
    Inc(Pass1Pos);
  end;

  if not SegAllocate(OutBuf, UncompressedLen + 1024) then
  begin
    SegFree(Pass1Buf);
    Exit;
  end;

  Pass2Pos := 0;
  P := 0;
  while P < Pass1Len do
  begin
    B := SegGetByte(Pass1Buf, P);
    if B = Esc1 then
    begin
      if P + 2 >= Pass1Len then Break;
      Val := SegGetByte(Pass1Buf, P + 1);
      Cnt := SegGetByte(Pass1Buf, P + 2);
      Inc(P, 3);
      for K := 1 to Cnt do
      begin
        SegSetByte(OutBuf, Pass2Pos, Val);
        Inc(Pass2Pos);
      end;
    end
    else if B = Esc2 then
    begin
      if P + 1 >= Pass1Len then Break;
      Cnt := SegGetByte(Pass1Buf, P + 1);
      Inc(P, 2);
      for K := 1 to Cnt do
      begin
        SegSetByte(OutBuf, Pass2Pos, Esc2Fill);
        Inc(Pass2Pos);
      end;
    end
    else if B = Esc3 then
    begin
      if P + 2 >= Pass1Len then Break;
      ChunkLen := SegGetByte(Pass1Buf, P + 1);
      RepeatCnt := SegGetByte(Pass1Buf, P + 2);
      if P + 3 + ChunkLen > Pass1Len then Break;
      for K := 1 to RepeatCnt do
      begin
        for J := 0 to ChunkLen - 1 do
        begin
          SegSetByte(OutBuf, Pass2Pos, SegGetByte(Pass1Buf, P + 3 + J));
          Inc(Pass2Pos);
        end;
      end;
      Inc(P, 3 + ChunkLen);
    end
    else
    begin
      SegSetByte(OutBuf, Pass2Pos, B);
      Inc(Pass2Pos);
      Inc(P);
    end;
  end;

  SegFree(Pass1Buf);

  if (UncompressedLen > 0) and (Pass2Pos >= UncompressedLen) then
    OutBuf.TotalSize := UncompressedLen
  else
    OutBuf.TotalSize := Pass2Pos;

  if (OutBuf.TotalSize >= 28) and (SegReadWordBE(OutBuf, 0) = $601A) then
    DecompressHappy := True
  else
    SegFree(OutBuf);
end;

{ =============================================================================
  JEK Packer / Byte Killer
  ============================================================================= }

function DecompressJek(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
var
  InSize, TextSize, DataSize, SymSize: LongInt;
  End1, End2, ActualEnd, OffsetVal, OutPtr, CmdVal, CountVal, OffVal, SrcVal: LongInt;
  XorKey, D0Val, CarryVal, WVal: LongInt;
  TempBuf: TSegBuffer;
  Candidates: array[0..2] of LongInt;
  NumCand, CandIdx: Integer;
  I, P, RelocBytes: LongInt;
  TextLen, DataLen, SymLen, TotalExp, TotalWithReloc, FirstReloc: LongInt;
  PrgStart: LongInt;
  NeededBlocks, Blk: Integer;
  JekEof: Boolean;

  function JekReadLong: LongInt;
  begin
    if OffsetVal < 4 then begin JekEof := True; JekReadLong := 0; Exit; end;
    Dec(OffsetVal, 4);
    JekReadLong := SegReadLongBE(InBuf, OffsetVal);
  end;

  function JekGetBit: LongInt;
  begin
    CarryVal := D0Val and 1;
    D0Val := (D0Val shr 1) and $7FFFFFFF;
    if D0Val = 0 then
    begin
      WVal := JekReadLong xor XorKey;
      CarryVal := WVal and 1;
      D0Val := ((WVal shr 1) and $7FFFFFFF) or $80000000;
    end;
    JekGetBit := CarryVal;
  end;

  function JekGetBits(N: Integer): LongInt;
  var K: Integer; Res: LongInt;
  begin
    Res := 0;
    for K := 1 to N do
      Res := (Res shl 1) or JekGetBit;
    JekGetBits := Res;
  end;

begin
  DecompressJek := False;
  InSize := InBuf.TotalSize;
  if InSize < 12 then Exit;

  NumCand := 0;
  if (InSize >= 28) and (SegGetByte(InBuf, 0) = $60) and
     ((SegGetByte(InBuf, 1) = $1A) or (SegGetByte(InBuf, 1) = $1C) or (SegGetByte(InBuf, 1) = 0)) then
  begin
    TextSize := SegReadLongBE(InBuf, 2);
    DataSize := SegReadLongBE(InBuf, 6);
    SymSize  := SegReadLongBE(InBuf, 14);
    if (TextSize < $1000000) and (DataSize < $1000000) and (SymSize < $1000000) then
    begin
      End1 := 28 + TextSize + DataSize;
      End2 := 28 + TextSize + DataSize + SymSize;
      if (End1 > 28) and (End1 <= InSize) then
      begin
        Candidates[NumCand] := End1;
        Inc(NumCand);
      end;
      if (End2 > 28) and (End2 <= InSize) and (End2 <> End1) then
      begin
        Candidates[NumCand] := End2;
        Inc(NumCand);
      end;
    end;
  end;
  Candidates[NumCand] := InSize;
  Inc(NumCand);

  for CandIdx := 0 to NumCand - 1 do
  begin
    ActualEnd := Candidates[CandIdx];
    if ActualEnd < 8 then Continue;

    OffsetVal := ActualEnd - 4;
    XorKey := SegReadLongBE(InBuf, OffsetVal);
    D0Val := 0;
    JekEof := False;

    if not SegAllocate(TempBuf, 262144) then Exit;
    OutPtr := TempBuf.TotalSize;

    while (OutPtr > 0) and (not JekEof) do
    begin
      if JekGetBit = 0 then
      begin
        if JekGetBit = 0 then
        begin
          CountVal := JekGetBits(3) + 1;
          for I := 1 to CountVal do
          begin
            Dec(OutPtr);
            if OutPtr >= 0 then
              SegSetByte(TempBuf, OutPtr, Byte(JekGetBits(8)));
          end;
        end
        else
        begin
          OffVal := JekGetBits(8);
          SrcVal := OutPtr + OffVal;
          for I := 1 to 2 do
          begin
            Dec(OutPtr);
            Dec(SrcVal);
            if (OutPtr >= 0) and (SrcVal >= 0) and (SrcVal < TempBuf.TotalSize) then
              SegSetByte(TempBuf, OutPtr, SegGetByte(TempBuf, SrcVal))
            else
              SegSetByte(TempBuf, OutPtr, 0);
          end;
        end;
      end
      else
      begin
        CmdVal := JekGetBits(2);
        if CmdVal = 0 then
        begin
          OffVal := JekGetBits(9);
          CountVal := 3;
        end
        else if CmdVal = 1 then
        begin
          OffVal := JekGetBits(10);
          CountVal := 4;
        end
        else if CmdVal = 2 then
        begin
          CountVal := JekGetBits(8) + 1;
          OffVal := JekGetBits(12);
        end
        else
        begin
          CountVal := JekGetBits(8) + 9;
          for I := 1 to CountVal do
          begin
            Dec(OutPtr);
            if OutPtr >= 0 then
              SegSetByte(TempBuf, OutPtr, Byte(JekGetBits(8)));
          end;
          Continue;
        end;

        SrcVal := OutPtr + OffVal;
        for I := 1 to CountVal do
        begin
          Dec(OutPtr);
          Dec(SrcVal);
          if (OutPtr >= 0) and (SrcVal >= 0) and (SrcVal < TempBuf.TotalSize) then
            SegSetByte(TempBuf, OutPtr, SegGetByte(TempBuf, SrcVal))
          else
            SegSetByte(TempBuf, OutPtr, 0);
        end;
      end;
    end;

    PrgStart := -1;
    TotalWithReloc := 0;
    for I := OutPtr to TempBuf.TotalSize - 28 do
    begin
      if (SegGetByte(TempBuf, I) = $60) and (SegGetByte(TempBuf, I + 1) = $1A) then
      begin
        TextLen := SegReadLongBE(TempBuf, I + 2);
        DataLen := SegReadLongBE(TempBuf, I + 6);
        SymLen  := SegReadLongBE(TempBuf, I + 14);
        if (TextLen > 0) and (TextLen < $100000) and (DataLen < $100000) and (SymLen < $100000) then
        begin
          TotalExp := 28 + TextLen + DataLen + SymLen;
          if (TotalExp > 0) and (TotalExp <= LongInt(TempBuf.TotalSize - I + 512)) then
          begin
            P := I + TotalExp;
            TotalWithReloc := TotalExp;
            if P + 4 <= TempBuf.TotalSize then
            begin
              FirstReloc := SegReadLongBE(TempBuf, P);
              if FirstReloc = 0 then
                Inc(TotalWithReloc, 4)
              else
              begin
                RelocBytes := 4;
                while (P + RelocBytes < TempBuf.TotalSize) and (SegGetByte(TempBuf, P + RelocBytes) <> 0) do
                  Inc(RelocBytes);
                if P + RelocBytes < TempBuf.TotalSize then Inc(RelocBytes);
                Inc(TotalWithReloc, RelocBytes);
              end;
            end;
            if I + TotalWithReloc > TempBuf.TotalSize then
              TotalWithReloc := TempBuf.TotalSize - I;
            PrgStart := I;
            Break;
          end;
        end;
      end;
    end;

    if PrgStart <> -1 then
    begin
      { Shift unpacked executable to start of buffer and free unused trailing blocks }
      for I := 0 to TotalWithReloc - 1 do
        SegSetByte(TempBuf, I, SegGetByte(TempBuf, PrgStart + I));

      NeededBlocks := (TotalWithReloc + 32767) div 32768;
      for Blk := NeededBlocks to TempBuf.NumBlocks - 1 do
      begin
        FreeMem(TempBuf.Blocks[Blk], 32768);
        TempBuf.Blocks[Blk] := nil;
      end;
      TempBuf.NumBlocks := NeededBlocks;
      TempBuf.TotalSize := TotalWithReloc;

      OutBuf := TempBuf;
      DecompressJek := True;
      Exit;
    end;

    SegFree(TempBuf);
  end;
end;

{ =============================================================================
  JAM Packer / LZH Dynamic Huffman Decompressor
  ============================================================================= }

const
  MAX_HUFF_COUNT = 314;
  LzhBitLengths: array[0..15] of Integer = (5, 5, 6, 6, 6, 7, 7, 7, 7, 8, 8, 8, 9, 9, 9, 10);
  LzhOffsets: array[0..15] of Integer = (
    0, 32, 64, 128, 192, 256, 384, 512, 640, 768, 1024, 1280, 1536, 2048, 2560, 3072);

type
  TDynNode = record
    Freq: Integer;
    Index: Integer;
    Parent: Integer;
    LeftLeaf: Integer;
    RightLeaf: Integer;
  end;

var
  JamNodes: array[0..MAX_HUFF_COUNT * 2 - 2] of TDynNode;
  JamCodeMap: array[0..MAX_HUFF_COUNT * 2 - 2] of Integer;

procedure DynHuffReset;
var
  I, J, L, R: Integer;
begin
  for I := 0 to MAX_HUFF_COUNT - 1 do
  begin
    JamNodes[I].Freq := 1;
    JamNodes[I].Index := I;
    JamNodes[I].Parent := MAX_HUFF_COUNT + (I shr 1);
    JamNodes[I].LeftLeaf := 0;
    JamNodes[I].RightLeaf := 0;
    JamCodeMap[I] := I;
  end;
  for I := MAX_HUFF_COUNT to MAX_HUFF_COUNT * 2 - 2 do
  begin
    J := (I - MAX_HUFF_COUNT) * 2;
    L := J;
    R := J + 1;
    JamNodes[I].Freq := JamNodes[L].Freq + JamNodes[R].Freq;
    JamNodes[I].Index := I;
    JamNodes[I].Parent := MAX_HUFF_COUNT + (I shr 1);
    JamNodes[I].LeftLeaf := L;
    JamNodes[I].RightLeaf := R;
    JamCodeMap[I] := I;
  end;
end;

function DynHuffDecode(var BitBuf: Byte;
  var BitCount: Integer;
  var InStreamOff, InStreamEnd: LongInt;
  var InBuf: TSegBuffer): Integer;
var
  Code: Integer;
  B: Byte;
begin
  Code := MAX_HUFF_COUNT * 2 - 2;
  while Code >= MAX_HUFF_COUNT do
  begin
    if BitCount = 0 then
    begin
      if InStreamOff <= InStreamEnd then
      begin
        DynHuffDecode := 0;
        Exit;
      end;
      Dec(InStreamOff);
      BitBuf := SegGetByte(InBuf, InStreamOff);
      BitCount := 8;
    end;
    B := (BitBuf shr 7) and 1;
    BitBuf := (BitBuf shl 1) and $FF;
    Dec(BitCount);
    if B = 1 then
      Code := JamNodes[Code].RightLeaf
    else
      Code := JamNodes[Code].LeftLeaf;
  end;
  DynHuffDecode := Code;
end;

procedure DynHuffUpdate(Code: Integer);
var
  Index, DestIndex, Freq, DestCode, TempIndex, TempCodeMap, TempParent: Integer;
  ParentA, ParentB: Integer;
begin
  if Code >= MAX_HUFF_COUNT then Exit;

  while Code <> MAX_HUFF_COUNT * 2 - 2 do
  begin
    Inc(JamNodes[Code].Freq);
    Index := JamNodes[Code].Index;
    DestIndex := Index;
    Freq := JamNodes[Code].Freq;

    while (DestIndex <> MAX_HUFF_COUNT * 2 - 2) and (Freq > JamNodes[JamCodeMap[DestIndex + 1]].Freq) do
      Inc(DestIndex);

    if Index <> DestIndex then
    begin
      DestCode := JamCodeMap[DestIndex];

      TempIndex := JamNodes[Code].Index;
      JamNodes[Code].Index := JamNodes[DestCode].Index;
      JamNodes[DestCode].Index := TempIndex;

      TempCodeMap := JamCodeMap[Index];
      JamCodeMap[Index] := JamCodeMap[DestIndex];
      JamCodeMap[DestIndex] := TempCodeMap;

      ParentA := JamNodes[Code].Parent;
      ParentB := JamNodes[DestCode].Parent;

      if JamNodes[ParentA].LeftLeaf = Code then
      begin
        if JamNodes[ParentB].LeftLeaf = DestCode then
        begin
          JamNodes[ParentA].LeftLeaf := DestCode;
          JamNodes[ParentB].LeftLeaf := Code;
        end
        else
        begin
          JamNodes[ParentA].LeftLeaf := DestCode;
          JamNodes[ParentB].RightLeaf := Code;
        end;
      end
      else
      begin
        if JamNodes[ParentB].LeftLeaf = DestCode then
        begin
          JamNodes[ParentA].RightLeaf := DestCode;
          JamNodes[ParentB].LeftLeaf := Code;
        end
        else
        begin
          JamNodes[ParentA].RightLeaf := DestCode;
          JamNodes[ParentB].RightLeaf := Code;
        end;
      end;

      TempParent := JamNodes[Code].Parent;
      JamNodes[Code].Parent := JamNodes[DestCode].Parent;
      JamNodes[DestCode].Parent := TempParent;
    end;
    Code := JamNodes[Code].Parent;
  end;
  Inc(JamNodes[Code].Freq);
end;

procedure DynHuffHalve;
var
  I, J, K, L, R, Freq, C, DestCode, TempIndex, TempParent, TempMap: Integer;
begin
  J := 0;
  for I := 0 to MAX_HUFF_COUNT * 2 - 2 do
  begin
    if J >= MAX_HUFF_COUNT then Break;
    if JamCodeMap[I] < MAX_HUFF_COUNT then
    begin
      JamNodes[JamCodeMap[I]].Index := J;
      Inc(J);
    end;
  end;

  for I := 0 to MAX_HUFF_COUNT - 1 do
  begin
    JamNodes[I].Freq := (JamNodes[I].Freq + 1) shr 1;
    JamNodes[I].Parent := MAX_HUFF_COUNT + (JamNodes[I].Index shr 1);
    JamCodeMap[JamNodes[I].Index] := I;
  end;

  J := 0;
  for I := MAX_HUFF_COUNT to MAX_HUFF_COUNT * 2 - 2 do
  begin
    L := JamCodeMap[J];
    R := JamCodeMap[J + 1];
    Freq := JamNodes[L].Freq + JamNodes[R].Freq;
    JamNodes[I].Freq := Freq;
    JamNodes[I].Index := I;
    JamNodes[I].Parent := MAX_HUFF_COUNT + (I shr 1);
    JamNodes[I].LeftLeaf := L;
    JamNodes[I].RightLeaf := R;
    JamCodeMap[I] := I;

    K := I;
    while (K > MAX_HUFF_COUNT) and (Freq < JamNodes[JamCodeMap[K - 1]].Freq) do
    begin
      C := JamCodeMap[K];
      DestCode := JamCodeMap[K - 1];

      TempIndex := JamNodes[C].Index;
      JamNodes[C].Index := JamNodes[DestCode].Index;
      JamNodes[DestCode].Index := TempIndex;

      TempParent := JamNodes[C].Parent;
      JamNodes[C].Parent := JamNodes[DestCode].Parent;
      JamNodes[DestCode].Parent := TempParent;

      TempMap := JamCodeMap[K];
      JamCodeMap[K] := JamCodeMap[K - 1];
      JamCodeMap[K - 1] := TempMap;
      Dec(K);
    end;
    Inc(J, 2);
  end;
end;

function ReadBitsFromStream(Count: Integer; var BitBuf: Byte; var BitCount: Integer;
                            var InStreamOff, InStreamEnd: LongInt; var InBuf: TSegBuffer): Integer;
var
  Res: Integer;
  B: Byte;
begin
  Res := 0;
  while Count > 0 do
  begin
    if BitCount = 0 then
    begin
      if InStreamOff <= InStreamEnd then begin ReadBitsFromStream := 0; Exit; end;
      Dec(InStreamOff);
      BitBuf := SegGetByte(InBuf, InStreamOff);
      BitCount := 8;
    end;
    B := (BitBuf shr 7) and 1;
    BitBuf := (BitBuf shl 1) and $FF;
    Dec(BitCount);
    Res := (Res shl 1) or B;
    Dec(Count);
  end;
  ReadBitsFromStream := Res;
end;

function DecompressLzhStream(var InBuf: TSegBuffer;
  HeaderOff: LongInt;
  RawSize, PackedSize: LongInt;
  var OutBuf: TSegBuffer): Boolean;
var
  InStreamOff, InStreamEnd, OutPos: LongInt;
  BitBuf: Byte;
  BitCount, Symbol, DistBase, Distance, CountVal, PrevCount, I: Integer;
begin
  DecompressLzhStream := False;
  if not SegAllocate(OutBuf, RawSize) then Exit;

  InStreamEnd := HeaderOff + 12;
  InStreamOff := HeaderOff + PackedSize;
  BitBuf := 0;
  BitCount := 0;
  OutPos := RawSize;

  DynHuffReset;

  while OutPos > 0 do
  begin
    Symbol := DynHuffDecode(BitBuf, BitCount, InStreamOff, InStreamEnd, InBuf);
    if JamNodes[MAX_HUFF_COUNT * 2 - 2].Freq = $8000 then
      DynHuffHalve;
    DynHuffUpdate(Symbol);

    if Symbol < 256 then
    begin
      Dec(OutPos);
      SegSetByte(OutBuf, OutPos, Byte(Symbol));
    end
    else
    begin
      DistBase := ReadBitsFromStream(4, BitBuf, BitCount, InStreamOff, InStreamEnd, InBuf);
      Distance := LzhOffsets[DistBase] +
        ReadBitsFromStream(LzhBitLengths[DistBase], BitBuf, BitCount, InStreamOff, InStreamEnd, InBuf) + 1;
      CountVal := Symbol - 253;

      PrevCount := 0;
      if OutPos + Distance > RawSize then
      begin
        PrevCount := CountVal;
        if OutPos + Distance - RawSize < PrevCount then
          PrevCount := OutPos + Distance - RawSize;
        for I := 1 to PrevCount do
        begin
          Dec(OutPos);
          SegSetByte(OutBuf, OutPos, $20);
        end;
      end;
      for I := PrevCount + 1 to CountVal do
      begin
        Dec(OutPos);
        SegSetByte(OutBuf, OutPos, SegGetByte(OutBuf, OutPos + Distance));
      end;
    end;
  end;

  OutBuf.TotalSize := RawSize;
  DecompressLzhStream := (OutPos <= 0);
  if OutPos > 0 then SegFree(OutBuf);
end;

function DecompressJam(var InBuf: TSegBuffer; var OutBuf: TSegBuffer): Boolean;
var
  InSize, Off, RawSize, PackedSize: LongInt;
  IsLsd, IsLzh: Boolean;
begin
  DecompressJam := False;
  InSize := InBuf.TotalSize;
  if InSize < 12 then Exit;

  for Off := 0 to InSize - 12 do
  begin
    if SegGetByte(InBuf, Off) = Byte('L') then
    begin
      IsLsd := (SegGetByte(InBuf, Off + 1) = Byte('S')) and
               (SegGetByte(InBuf, Off + 2) = Byte('D')) and
               (SegGetByte(InBuf, Off + 3) = Byte('!'));
      IsLzh := (SegGetByte(InBuf, Off + 1) = Byte('Z')) and
               (SegGetByte(InBuf, Off + 2) = Byte('H')) and
               (SegGetByte(InBuf, Off + 3) = Byte('!'));
      if IsLsd or IsLzh then
      begin
        RawSize := SegReadLongBE(InBuf, Off + 4);
        PackedSize := SegReadLongBE(InBuf, Off + 8);
        if IsLsd then Inc(PackedSize, 4)
        else if IsLzh then Inc(PackedSize, 12);

        if (PackedSize > 0) and (PackedSize <= InSize) and (Off <= InSize - PackedSize) and
           (RawSize > 0) and (RawSize <= 524288) then
        begin
          if IsLsd then
          begin
            if DecompressAutomation(InBuf, OutBuf) then
            begin
              DecompressJam := True;
              Exit;
            end;
          end
          else if IsLzh then
          begin
            if DecompressLzhStream(InBuf, Off, RawSize, PackedSize, OutBuf) then
            begin
              DecompressJam := True;
              Exit;
            end;
          end;
        end;
      end;
    end;
  end;
end;

{ =============================================================================
  Master Universal Depacker Dispatcher
  ============================================================================= }

function DepackUniversal(const InPath, OutPath: string; var PackerName: string; var DepackedSize: LongInt): Boolean;
var
  InBuf, OutBuf: TSegBuffer;
  Ok: Boolean;
  Tag: string;
begin
  DepackUniversal := False;
  PackerName := 'Unknown';
  DepackedSize := 0;

  if not SegLoadFromFile(InBuf, InPath) then Exit;

  Tag := DetectBufferPacker(InBuf);
  Ok := False;

  if (Pos('FIRE', Tag) > 0) or (Pos('Pack-Fire', Tag) > 0) then
  begin
    Ok := DecompressFire(InBuf, OutBuf);
    if Ok then PackerName := 'FIRE Packer';
  end
  else if (Pos('PowerPacker', Tag) > 0) or (Pos('PP20', Tag) > 0) then
  begin
    Ok := DecompressPowerPacker(InBuf, OutBuf);
    if Ok then PackerName := 'PowerPacker (PP20)';
  end
  else if (Pos('Thunder', Tag) > 0) or (Pos('ATOM', Tag) > 0) then
  begin
    Ok := DecompressThunder(InBuf, OutBuf);
    if Ok then PackerName := 'Thunder Packer';
  end
  else if (Pos('Squash', Tag) > 0) or (Pos('SQSH', Tag) > 0) then
  begin
    Ok := DecompressStosSquash(InBuf, OutBuf);
    if Ok then PackerName := 'STOS Squashed Data';
  end
  else if (Pos('4PAK', Tag) > 0) then
  begin
    Ok := Decompress4PAK(InBuf, OutBuf);
    if Ok then PackerName := '4PAK Executable';
  end
  else if (Pos('Sentry', Tag) > 0) then
  begin
    Ok := DecompressSentry(InBuf, OutBuf);
    if Ok then PackerName := 'Sentry Packer';
  end
  else if (Pos('STAD', Tag) > 0) then
  begin
    Ok := DecompressStad(InBuf, OutBuf);
    if Ok then PackerName := 'STAD Monochrome Image';
  end
  else if (Pos('Happy', Tag) > 0) then
  begin
    Ok := DecompressHappy(InBuf, OutBuf);
    if Ok then PackerName := 'Happy Packer';
  end
  else if (Pos('JEK', Tag) > 0) or (Pos('Byte Killer', Tag) > 0) then
  begin
    Ok := DecompressJek(InBuf, OutBuf);
    if Ok then PackerName := 'JEK Packer';
  end
  else if (Pos('JAM', Tag) > 0) or (Pos('LZH', Tag) > 0) then
  begin
    Ok := DecompressJam(InBuf, OutBuf);
    if Ok then PackerName := 'JAM Packer';
  end
  else if Pos('Degas', Tag) > 0 then
  begin
    Ok := DecompressDegasPC(InBuf, OutBuf);
    if Ok then
    begin
      if Pos('PC2', Tag) > 0 then PackerName := 'Degas Elite PC2'
      else if Pos('PC3', Tag) > 0 then PackerName := 'Degas Elite PC3'
      else PackerName := 'Degas Elite PC1';
    end;
  end
  else if Pos('Titus', Tag) > 0 then
  begin
    Ok := DecompressTitusPC1(InBuf, OutBuf);
    if Ok then PackerName := 'Titus PC1 (LZW)';
  end
  else if Pos('RNC', Tag) > 0 then
  begin
    Ok := DecompressRNC(InBuf, OutBuf);
    if Ok then PackerName := 'Rob Northen RNC';
  end
  else if Pos('Pack-Ice', Tag) > 0 then
  begin
    Ok := DecompressPackIce(InBuf, OutBuf);
    if Ok then PackerName := 'Pack-Ice';
  end
  else if Pos('Atomik', Tag) > 0 then
  begin
    Ok := DecompressAtomik(InBuf, OutBuf);
    if Ok then PackerName := 'Atomik Cruncher';
  end
  else if Pos('Pompey', Tag) > 0 then
  begin
    Ok := DecompressPompey(InBuf, OutBuf);
    if Ok then PackerName := 'Pompey Pirates';
  end
  else if Pos('Automation', Tag) > 0 then
  begin
    Ok := DecompressAutomation(InBuf, OutBuf);
    if Ok then PackerName := 'Automation Packer';
  end
  else
  begin
    { Fallback trial chain }
    if not Ok then begin Ok := DecompressPackIce(InBuf, OutBuf); if Ok then PackerName := 'Pack-Ice'; end;
    if not Ok then begin Ok := DecompressAtomik(InBuf, OutBuf); if Ok then PackerName := 'Atomik Cruncher'; end;
    if not Ok then begin Ok := DecompressRNC(InBuf, OutBuf); if Ok then PackerName := 'Rob Northen RNC'; end;
    if not Ok then begin Ok := DecompressPompey(InBuf, OutBuf); if Ok then PackerName := 'Pompey Pirates'; end;
    if not Ok then begin Ok := DecompressAutomation(InBuf, OutBuf); if Ok then PackerName := 'Automation Packer'; end;
    if not Ok then begin Ok := DecompressHappy(InBuf, OutBuf); if Ok then PackerName := 'Happy Packer'; end;
    if not Ok then begin Ok := DecompressJek(InBuf, OutBuf); if Ok then PackerName := 'JEK Packer'; end;
    if not Ok then begin Ok := DecompressJam(InBuf, OutBuf); if Ok then PackerName := 'JAM Packer'; end;
    if not Ok then begin Ok := DecompressFire(InBuf, OutBuf); if Ok then PackerName := 'FIRE Packer'; end;
    if not Ok then begin Ok := DecompressPowerPacker(InBuf, OutBuf); if Ok then PackerName := 'PowerPacker (PP20)'; end;
    if not Ok then begin Ok := DecompressThunder(InBuf, OutBuf); if Ok then PackerName := 'Thunder Packer'; end;
    if not Ok then begin Ok := DecompressStosSquash(InBuf, OutBuf); if Ok then PackerName := 'STOS Squashed Data'; end;
    if not Ok then begin Ok := Decompress4PAK(InBuf, OutBuf); if Ok then PackerName := '4PAK Executable'; end;
    if not Ok then begin Ok := DecompressSentry(InBuf, OutBuf); if Ok then PackerName := 'Sentry Packer'; end;
    if not Ok then begin Ok := DecompressStad(InBuf, OutBuf); if Ok then PackerName := 'STAD Monochrome Image'; end;
  end;

  if Ok then
  begin
    DepackedSize := OutBuf.TotalSize;
    Ok := SegSaveToFile(OutBuf, OutPath, DepackedSize);
    SegFree(OutBuf);
  end;

  SegFree(InBuf);
  DepackUniversal := Ok;
end;

end.
