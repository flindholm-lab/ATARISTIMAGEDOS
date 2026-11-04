program FastView;

{$M 8192, 0, 65536}  { Stack: 8 KB, Heap: up to 64 KB }
{$A-,G-,R-,S-,I-,Q-} { 8086 real-mode code, byte-aligned, runtime checks disabled }

uses Dos;

type
  TFormat = (fmtUnknown, fmtBMP, fmtGIF, fmtJPG,
             fmtDegasPI1, fmtDegasPI2, fmtDegasPI3,
             fmtDegasPC1, fmtDegasPC2, fmtDegasPC3,
             fmtNeoChrome, fmtArtDirector, fmtDoodle);

  { BMP Headers }
  TBitmapFileHeader = record
    bfType:      Word;
    bfSize:      LongInt;
    bfReserved1: Word;
    bfReserved2: Word;
    bfOffBits:   LongInt;
  end;

  TBitmapInfoHeader = record
    biSize:          LongInt;
    biWidth:         LongInt;
    biHeight:        LongInt;
    biPlanes:        Word;
    biBitCount:      Word;
    biCompression:   LongInt;
    biSizeImage:     LongInt;
    biXPelsPerMeter: LongInt;
    biYPelsPerMeter: LongInt;
    biClrUsed:       LongInt;
    biClrImportant:  LongInt;
  end;

  { GIF Structures }
  TLSD = record
    ScreenWidth:  Word;
    ScreenHeight: Word;
    PackedFields: Byte;
    BgColor:      Byte;
    AspectRatio:  Byte;
  end;

  TImageDesc = record
    Left:         Word;
    Top:          Word;
    Width:        Word;
    Height:       Word;
    PackedFields: Byte;
  end;

  { JPEG Structures }
  TJPEGComp = record
    Id:     Byte;
    H, V:   Byte;
    QTIdx:  Byte;
    DCTbl:  Byte;
    ACTbl:  Byte;
    PrevDC: Integer;
  end;

  { Color-Pair Dither Cell }
  TDitherCell = record
    C1:     Byte;
    C2:     Byte;
    Thresh: Byte; { 0..16 valid duty cycle; 255 = uncalculated sentinel }
  end;

const
  ZigZag: array[0..63] of Byte = (
      0,  1,  8, 16,  9,  2,  3, 10,
     17, 24, 32, 25, 18, 11,  4,  5,
     12, 19, 26, 33, 40, 48, 41, 34,
     27, 20, 13,  6,  7, 14, 21, 28,
     35, 42, 49, 56, 57, 50, 43, 36,
     29, 22, 15, 23, 30, 37, 44, 51,
     58, 59, 52, 45, 38, 31, 39, 46,
     53, 60, 61, 54, 47, 55, 62, 63
  );

  { Standard 0..15 Bayer Dither Matrix }
  Bayer4x4: array[0..3, 0..3] of Byte = (
    ( 0,  8,  2, 10),
    (12,  4, 14,  6),
    ( 3, 11,  1,  9),
    (15,  7, 13,  5)
  );

  PassStart: array[0..3] of Word = (0, 4, 2, 1);
  PassStep:  array[0..3] of Word = (8, 8, 4, 2);

  { Standard 16-color EGA Hardware Palette (RGB values 0..255) }
  EGAPalRGB: array[0..15, 0..2] of Byte = (
    (0,0,0),       (0,0,170),     (0,170,0),     (0,170,170),
    (170,0,0),     (170,0,170),   (170,85,0),    (170,170,170),
    (85,85,85),    (85,85,255),   (85,255,85),   (85,255,255),
    (255,85,85),   (255,85,255),  (255,255,85),  (255,255,255)
  );

  { Standard CGA Mode 04h Palette 1 (High Intensity) }
  CGAPalRGB: array[0..3, 0..2] of Byte = (
    (0,0,0),       (85,255,255),  (255,85,255),  (255,255,255)
  );

var
  ImgFile: file;
  FileName: string;
  TargetMode: Word;   { $13 = VGA, $0D = EGA, $04 = CGA }
  IsMono: Boolean;
  UserAborted: Boolean;

  { Fast VGA Quantization LUTs }
  Quant8: array[0..255] of Byte;
  Quant4: array[0..255] of Byte;

  { Active Hardware Palette Structures }
  PalCount:  Integer;
  Pal:       array[0..15, 0..2] of Integer;
  PalIdxMap: array[0..15] of Byte;
  PairVr:    array[0..15, 0..15] of Integer;
  PairVg:    array[0..15, 0..15] of Integer;
  PairVb:    array[0..15, 0..15] of Integer;
  PairVsq:   array[0..15, 0..15] of LongInt;

  { Dynamic Color-Pair Dither Cache (12 KB) }
  DitherLUT: array[0..15, 0..15, 0..15] of TDitherCell;

  { Shared Image Buffers }
  PaletteBuf:  array[0..767] of Byte;
  ScanLineBuf: array[0..6143] of Byte;
  MapX:        array[0..2047] of Word;
  MapY:        array[0..2047] of Word;

  { GIF Decompressor State }
  PrefixTable: array[0..4095] of Word;
  SuffixTable: array[0..4095] of Byte;
  PixelStack:  array[0..4095] of Byte;
  BlockBuf:    array[0..255] of Byte;
  BlockLen, BlockPos: Byte;
  BitBuffer:   LongInt;
  BitsInBuf:   Integer;
  StreamDone:  Boolean;

  { JPEG Tables & Buffers }
  QTable:      array[0..3, 0..63] of Integer;
  HuffBits:    array[0..3, 1..16] of Byte;
  HuffVal:     array[0..3, 0..255] of Byte;
  MinCode:     array[0..3, 1..16] of Integer;
  MaxCode:     array[0..3, 1..16] of Integer;
  ValPtr:      array[0..3, 1..16] of Integer;
  CTable:      array[0..7, 0..7] of Integer;
  Comps:       array[0..2] of TJPEGComp;
  NumComps:    Integer;
  JWidth, JHeight: Word;

  { JPEG Buffered Bitstream }
  JStreamBuf:  array[0..511] of Byte;
  JStreamPos:  Word;
  JStreamLen:  Word;
  JBitBuf:     LongInt;
  JBitsLeft:   Integer;

{ --- BIOS Video & Input Handling --- }

procedure SetVideoMode(Mode: Byte);
var
  Regs: Registers;
begin
  Regs.AH := $00;
  Regs.AL := Mode;
  Intr($10, Regs);
end;

function WaitForKey: Char;
var
  Regs: Registers;
begin
  Regs.AH := $00;
  Intr($16, Regs);
  WaitForKey := Chr(Regs.AL);
end;

{ Fast non-blocking key check: reads BIOS circular buffer head/tail directly }
function CheckUserAbort: Boolean;
var
  Regs: Registers;
begin
  if MemW[$0040:$001A] <> MemW[$0040:$001C] then
  begin
    { Consume the keystroke and only abort if Esc key was pressed }
    Regs.AH := $00;
    Intr($16, Regs);
    if (Regs.AL = 27) or (Regs.AH = 1) then
      CheckUserAbort := True
    else
      CheckUserAbort := False;
  end
  else
    CheckUserAbort := False;
end;

function AutoDetectAdapter: Word;
var
  Regs: Registers;
begin
  Regs.AH := $1A;
  Regs.AL := $00;
  Intr($10, Regs);
  if (Regs.AL = $1A) and ((Regs.BL = $07) or (Regs.BL = $08)) then
  begin
    AutoDetectAdapter := $13;
    Exit;
  end;

  Regs.AH := $12;
  Regs.BL := $10;
  Intr($10, Regs);
  if Regs.BL <> $10 then
  begin
    AutoDetectAdapter := $0D;
    Exit;
  end;

  AutoDetectAdapter := $04;
end;

procedure InitVideo;
begin
  SetVideoMode(Lo(TargetMode));
  if TargetMode = $0D then
  begin
    Port[$03CE] := 5; Port[$03CF] := 2; { EGA Write Mode 2 }
    Port[$03CE] := 1; Port[$03CF] := 0;
  end;
end;

procedure CloseVideo;
begin
  if TargetMode = $0D then
  begin
    Port[$03CE] := 5; Port[$03CF] := 0;
    Port[$03CE] := 8; Port[$03CF] := $FF;
  end;
  SetVideoMode($03);
end;

procedure SetVGAPaletteDirect(StartIdx, Count: Word);
var
  I, P: Word;
begin
  Port[$03C8] := StartIdx;
  P := StartIdx * 3;
  for I := 0 to (Count * 3) - 1 do
  begin
    Port[$03C9] := PaletteBuf[P];
    Inc(P);
  end;
end;

procedure SetupRGB332Palette;
var
  R, G, B, Idx: Word;
begin
  for R := 0 to 7 do
    for G := 0 to 7 do
      for B := 0 to 3 do
      begin
        Idx := (R shl 5) or (G shl 2) or B;
        PaletteBuf[Idx * 3 + 0] := (R * 63 + 3) div 7;
        PaletteBuf[Idx * 3 + 1] := (G * 63 + 3) div 7;
        PaletteBuf[Idx * 3 + 2] := (B * 63 + 1) div 3;
      end;
  SetVGAPaletteDirect(0, 256);
end;

procedure SetupVGAMonoPalette;
var
  I: Word;
  Gray6: Byte;
begin
  Port[$03C8] := 0;
  for I := 0 to 255 do
  begin
    Gray6 := (I * 63 + 128) div 255;
    Port[$03C9] := Gray6;
    Port[$03C9] := Gray6;
    Port[$03C9] := Gray6;
  end;
end;

procedure BuildColorLUTs;
var
  R, I, J: Integer;
  Vr, Vg, Vb: Integer;
begin
  for R := 0 to 255 do
  begin
    Quant8[R] := (R * 7 + 128) div 255;
    Quant4[R] := (R * 3 + 128) div 255;
  end;

  if TargetMode = $13 then Exit;

  if TargetMode = $0D then
  begin
    if IsMono then
    begin
      PalCount := 4;
      Pal[0,0]:=0;   Pal[0,1]:=0;   Pal[0,2]:=0;   PalIdxMap[0]:=0;
      Pal[1,0]:=85;  Pal[1,1]:=85;  Pal[1,2]:=85;  PalIdxMap[1]:=8;
      Pal[2,0]:=170; Pal[2,1]:=170; Pal[2,2]:=170; PalIdxMap[2]:=7;
      Pal[3,0]:=255; Pal[3,1]:=255; Pal[3,2]:=255; PalIdxMap[3]:=15;
    end
    else
    begin
      PalCount := 16;
      for I := 0 to 15 do
      begin
        Pal[I, 0] := EGAPalRGB[I, 0];
        Pal[I, 1] := EGAPalRGB[I, 1];
        Pal[I, 2] := EGAPalRGB[I, 2];
        PalIdxMap[I] := I;
      end;
    end;
  end
  else
  begin
    if IsMono then
    begin
      PalCount := 2;
      Pal[0,0]:=0;   Pal[0,1]:=0;   Pal[0,2]:=0;   PalIdxMap[0]:=0;
      Pal[1,0]:=255; Pal[1,1]:=255; Pal[1,2]:=255; PalIdxMap[1]:=3;
    end
    else
    begin
      PalCount := 4;
      for I := 0 to 3 do
      begin
        Pal[I, 0] := CGAPalRGB[I, 0];
        Pal[I, 1] := CGAPalRGB[I, 1];
        Pal[I, 2] := CGAPalRGB[I, 2];
        PalIdxMap[I] := I;
      end;
    end;
  end;

  for I := 0 to PalCount - 1 do
    for J := 0 to PalCount - 1 do
    begin
      Vr := Pal[I, 0] - Pal[J, 0];
      Vg := Pal[I, 1] - Pal[J, 1];
      Vb := Pal[I, 2] - Pal[J, 2];
      PairVr[I, J] := Vr;
      PairVg[I, J] := Vg;
      PairVb[I, J] := Vb;
      PairVsq[I, J] := LongInt(Vr)*Vr + LongInt(Vg)*Vg + LongInt(Vb)*Vb;
    end;

  FillChar(DitherLUT, SizeOf(DitherLUT), 255);
end;

procedure ComputeDitherCell(R4, G4, B4: Integer);
var
  Tr, Tg, Tb, Lum: Integer;
  Cand: array[0..3] of Integer;
  CandDist: array[0..3] of LongInt;
  NumCand, I, J, Ci, Cj, K, W: Integer;
  Dr, Dg, Db, Mr, Mg, Mb: Integer;
  Dist, BestDist, Dot, Vsq: LongInt;
  BestC1, BestC2: Byte;
  BestW: Integer;
begin
  Tr := R4 * 17;
  Tg := G4 * 17;
  Tb := B4 * 17;

  if IsMono then
  begin
    Lum := (Tr * 77 + Tg * 150 + Tb * 29) shr 8;
    Tr := Lum; Tg := Lum; Tb := Lum;
  end;

  NumCand := PalCount;
  if NumCand > 4 then NumCand := 4;
  for I := 0 to 3 do CandDist[I] := $7FFFFFFF;

  for I := 0 to PalCount - 1 do
  begin
    Dr := Pal[I, 0] - Tr;
    Dg := Pal[I, 1] - Tg;
    Db := Pal[I, 2] - Tb;
    Dist := LongInt(Dr)*Dr*30 + LongInt(Dg)*Dg*59 + LongInt(Db)*Db*11;

    if Dist < CandDist[NumCand - 1] then
    begin
      K := NumCand - 1;
      while (K > 0) and (Dist < CandDist[K - 1]) do
      begin
        CandDist[K] := CandDist[K - 1];
        Cand[K] := Cand[K - 1];
        Dec(K);
      end;
      CandDist[K] := Dist;
      Cand[K] := I;
    end;
  end;

  BestDist := $7FFFFFFF;
  BestC1 := PalIdxMap[Cand[0]];
  BestC2 := PalIdxMap[Cand[0]];
  BestW := 16;

  for Ci := 0 to NumCand - 1 do
  begin
    I := Cand[Ci];
    Dr := Pal[I, 0] - Tr;
    Dg := Pal[I, 1] - Tg;
    Db := Pal[I, 2] - Tb;
    Dist := LongInt(Dr)*Dr*30 + LongInt(Dg)*Dg*59 + LongInt(Db)*Db*11;
    if Dist < BestDist then
    begin
      BestDist := Dist;
      BestC1 := PalIdxMap[I];
      BestC2 := PalIdxMap[I];
      BestW := 16;
    end;

    for Cj := Ci + 1 to NumCand - 1 do
    begin
      J := Cand[Cj];
      Vsq := PairVsq[I, J];
      if Vsq > 0 then
      begin
        Dot := LongInt(Tr - Pal[J, 0]) * PairVr[I, J] +
               LongInt(Tg - Pal[J, 1]) * PairVg[I, J] +
               LongInt(Tb - Pal[J, 2]) * PairVb[I, J];

        W := Integer((Dot * 16 + (Vsq shr 1)) div Vsq);
        if W < 0 then W := 0 else if W > 16 then W := 16;

        Mr := (W * Pal[I, 0] + (16 - W) * Pal[J, 0] + 8) shr 4;
        Mg := (W * Pal[I, 1] + (16 - W) * Pal[J, 1] + 8) shr 4;
        Mb := (W * Pal[I, 2] + (16 - W) * Pal[J, 2] + 8) shr 4;

        Dr := Mr - Tr;
        Dg := Mg - Tg;
        Db := Mb - Tb;
        Dist := LongInt(Dr)*Dr*30 + LongInt(Dg)*Dg*59 + LongInt(Db)*Db*11;

        if Dist < BestDist then
        begin
          BestDist := Dist;
          BestC1 := PalIdxMap[I];
          BestC2 := PalIdxMap[J];
          BestW := W;
        end;
      end;
    end;
  end;

  DitherLUT[R4, G4, B4].C1 := BestC1;
  DitherLUT[R4, G4, B4].C2 := BestC2;
  DitherLUT[R4, G4, B4].Thresh := BestW;
end;

procedure PutPixelRGB(X, Y: Word; R, G, B: Integer);
var
  Ofs: Word;
  Shift, Mask, Color, Dummy: Byte;
  Bias, Lum: Integer;
  R4, G4, B4: Integer;
begin
  if (X >= 320) or (Y >= 200) then Exit;

  case TargetMode of
    $13:
      begin
        Bias := Integer(Bayer4x4[Y and 3, X and 3]) - 8;
        if IsMono then
        begin
          Lum := Integer((LongInt(R) * 77 + LongInt(G) * 150 + LongInt(B) * 29) shr 8) + Bias;
          if Lum < 0 then Lum := 0 else if Lum > 255 then Lum := 255;
          Mem[$A000:(Y * 320) + X] := Byte(Lum);
        end
        else
        begin
          R := R + (Bias * 36) div 16; if R < 0 then R := 0 else if R > 255 then R := 255;
          G := G + (Bias * 36) div 16; if G < 0 then G := 0 else if G > 255 then G := 255;
          B := B + (Bias * 85) div 16; if B < 0 then B := 0 else if B > 255 then B := 255;
          Mem[$A000:(Y * 320) + X] := (Quant8[R] shl 5) or (Quant8[G] shl 2) or Quant4[B];
        end;
      end;

    $0D:
      begin
        if R < 0 then R := 0 else if R > 255 then R := 255;
        if G < 0 then G := 0 else if G > 255 then G := 255;
        if B < 0 then B := 0 else if B > 255 then B := 255;

        R4 := R shr 4; G4 := G shr 4; B4 := B shr 4;
        if DitherLUT[R4, G4, B4].Thresh = 255 then
          ComputeDitherCell(R4, G4, B4);

        if Bayer4x4[Y and 3, X and 3] < DitherLUT[R4, G4, B4].Thresh then
          Color := DitherLUT[R4, G4, B4].C1
        else
          Color := DitherLUT[R4, G4, B4].C2;

        Ofs := Y * 40 + (X shr 3);
        Port[$03CE] := 8;
        Port[$03CF] := $80 shr (X and 7);
        Dummy := Mem[$A000:Ofs];
        Mem[$A000:Ofs] := Color;
      end;

    $04:
      begin
        if R < 0 then R := 0 else if R > 255 then R := 255;
        if G < 0 then G := 0 else if G > 255 then G := 255;
        if B < 0 then B := 0 else if B > 255 then B := 255;

        R4 := R shr 4; G4 := G shr 4; B4 := B shr 4;
        if DitherLUT[R4, G4, B4].Thresh = 255 then
          ComputeDitherCell(R4, G4, B4);

        if Bayer4x4[Y and 3, X and 3] < DitherLUT[R4, G4, B4].Thresh then
          Color := DitherLUT[R4, G4, B4].C1
        else
          Color := DitherLUT[R4, G4, B4].C2;

        Ofs := (Y shr 1) * 80 + (X shr 2);
        if (Y and 1) <> 0 then Inc(Ofs, $2000);
        Shift := 6 - ((X and 3) shl 1);
        Mask := not ($03 shl Shift);
        Mem[$B800:Ofs] := (Mem[$B800:Ofs] and Mask) or (Color shl Shift);
      end;
  end;
end;

procedure BuildScalingMaps(SrcW, SrcH: Word);
var
  I, OffX, OffY: Word;
begin
  if (SrcW = 0) or (SrcH = 0) then Exit;

  if SrcW >= 320 then
    for I := 0 to 2047 do MapX[I] := (LongInt(I) * 320) div SrcW
  else
  begin
    OffX := (320 - SrcW) div 2;
    for I := 0 to 2047 do
      if I < SrcW then MapX[I] := I + OffX else MapX[I] := SrcW - 1 + OffX;
  end;

  if SrcH >= 200 then
    for I := 0 to 2047 do MapY[I] := (LongInt(I) * 200) div SrcH
  else
  begin
    OffY := (200 - SrcH) div 2;
    for I := 0 to 2047 do
      if I < SrcH then MapY[I] := I + OffY else MapY[I] := SrcH - 1 + OffY;
  end;
end;

function DetectFormat: TFormat;
var
  Magic: array[0..3] of Byte;
  ReadBytes: Word;
  Ext: string[4];
  I: Integer;
  Fs: LongInt;
begin
  Seek(ImgFile, 0);
  BlockRead(ImgFile, Magic, 4, ReadBytes);
  Seek(ImgFile, 0);

  if (Magic[0] = $42) and (Magic[1] = $4D) then DetectFormat := fmtBMP
  else if (Magic[0] = $47) and (Magic[1] = $49) and (Magic[2] = $46) then DetectFormat := fmtGIF
  else if (Magic[0] = $FF) and (Magic[1] = $D8) then DetectFormat := fmtJPG
  else
  begin
    Ext := '';
    if Length(FileName) >= 4 then
      Ext := Copy(FileName, Length(FileName) - 3, 4);
    for I := 1 to Length(Ext) do Ext[I] := UpCase(Ext[I]);

    Fs := FileSize(ImgFile);

    if (Ext = '.PI1') or ((Magic[0] = 0) and (Magic[1] = 0) and (Fs = 32034)) then
      DetectFormat := fmtDegasPI1
    else if (Ext = '.PI2') or ((Magic[0] = 0) and (Magic[1] = 1) and (Fs = 32034)) then
      DetectFormat := fmtDegasPI2
    else if (Ext = '.PI3') or ((Magic[0] = 0) and (Magic[1] = 2) and (Fs = 32034)) then
      DetectFormat := fmtDegasPI3
    else if (Ext = '.PC1') or ((Magic[0] = $80) and (Magic[1] = 0)) then
      DetectFormat := fmtDegasPC1
    else if (Ext = '.PC2') or ((Magic[0] = $80) and (Magic[1] = 1)) then
      DetectFormat := fmtDegasPC2
    else if (Ext = '.PC3') or ((Magic[0] = $80) and (Magic[1] = 2)) then
      DetectFormat := fmtDegasPC3
    else if (Ext = '.NEO') or (Fs = 32128) then
      DetectFormat := fmtNeoChrome
    else if (Ext = '.ART') or (Fs = 32032) then
      DetectFormat := fmtArtDirector
    else if (Ext = '.DOO') or ((Ext = '.SCR') and (Fs = 32000)) then
      DetectFormat := fmtDoodle
    else if (Ext = '.DEG') then
    begin
      if Magic[0] = $80 then
      begin
        if Magic[1] = 1 then DetectFormat := fmtDegasPC2
        else if Magic[1] = 2 then DetectFormat := fmtDegasPC3
        else DetectFormat := fmtDegasPC1;
      end
      else
      begin
        if Magic[1] = 1 then DetectFormat := fmtDegasPI2
        else if Magic[1] = 2 then DetectFormat := fmtDegasPI3
        else DetectFormat := fmtDegasPI1;
      end;
    end
    else
      DetectFormat := fmtUnknown;
  end;
end;

procedure SetupAtariPalette(const RawPal: array of Byte);
var
  I: Integer;
  ColWord: Word;
  R, G, B: Byte;
begin
  for I := 0 to 15 do
  begin
    ColWord := (Word(RawPal[I * 2]) shl 8) or RawPal[I * 2 + 1];
    R := ((ColWord shr 8) and 7) * 36;
    G := ((ColWord shr 4) and 7) * 36;
    B := (ColWord and 7) * 36;
    PaletteBuf[I * 3 + 0] := R;
    PaletteBuf[I * 3 + 1] := G;
    PaletteBuf[I * 3 + 2] := B;
  end;

  if (TargetMode = $13) and (not IsMono) then
  begin
    Port[$03C8] := 0;
    for I := 0 to 47 do
      Port[$03C9] := PaletteBuf[I] shr 2;
  end;
end;

procedure RenderAtariScanline(Y: Integer; const LineBuf: array of Byte);
var
  BlockX, Pix, Off: Integer;
  P0, P1, P2, P3: Word;
  Color: Byte;
  BitMask: Word;
  ScreenX: Integer;
begin
  if (Y < 0) or (Y >= 200) then Exit;
  for BlockX := 0 to 19 do
  begin
    Off := BlockX * 8;
    P0 := (Word(LineBuf[Off + 0]) shl 8) or LineBuf[Off + 1];
    P1 := (Word(LineBuf[Off + 2]) shl 8) or LineBuf[Off + 3];
    P2 := (Word(LineBuf[Off + 4]) shl 8) or LineBuf[Off + 5];
    P3 := (Word(LineBuf[Off + 6]) shl 8) or LineBuf[Off + 7];

    for Pix := 0 to 15 do
    begin
      BitMask := 1 shl (15 - Pix);
      Color := 0;
      if (P0 and BitMask) <> 0 then Inc(Color, 1);
      if (P1 and BitMask) <> 0 then Inc(Color, 2);
      if (P2 and BitMask) <> 0 then Inc(Color, 4);
      if (P3 and BitMask) <> 0 then Inc(Color, 8);

      ScreenX := BlockX * 16 + Pix;
      if (TargetMode = $13) and (not IsMono) then
        Mem[$A000:(Y * 320) + ScreenX] := Color
      else
        PutPixelRGB(ScreenX, Y, PaletteBuf[Color * 3 + 0],
          PaletteBuf[Color * 3 + 1], PaletteBuf[Color * 3 + 2]);
    end;
  end;
end;

procedure RenderDegasPI1;
var
  ResWord: Word;
  RawPal: array[0..31] of Byte;
  LineBuf: array[0..159] of Byte;
  Y: Integer;
  ReadBytes: Word;
begin
  Seek(ImgFile, 0);
  BlockRead(ImgFile, ResWord, 2, ReadBytes);
  BlockRead(ImgFile, RawPal, 32, ReadBytes);
  SetupAtariPalette(RawPal);

  for Y := 0 to 199 do
  begin
    if CheckUserAbort then
    begin
      UserAborted := True;
      Exit;
    end;
    BlockRead(ImgFile, LineBuf, 160, ReadBytes);
    RenderAtariScanline(Y, LineBuf);
  end;
end;

procedure RenderNeoChrome;
var
  Hdr: array[0..3] of Byte;
  RawPal: array[0..31] of Byte;
  LineBuf: array[0..159] of Byte;
  Y: Integer;
  ReadBytes: Word;
begin
  Seek(ImgFile, 0);
  BlockRead(ImgFile, Hdr, 4, ReadBytes);
  BlockRead(ImgFile, RawPal, 32, ReadBytes);
  SetupAtariPalette(RawPal);
  Seek(ImgFile, 128);

  for Y := 0 to 199 do
  begin
    if CheckUserAbort then
    begin
      UserAborted := True;
      Exit;
    end;
    BlockRead(ImgFile, LineBuf, 160, ReadBytes);
    RenderAtariScanline(Y, LineBuf);
  end;
end;

procedure RenderDegasPC1;
var
  ResWord: Word;
  RawPal: array[0..31] of Byte;
  Planes: array[0..3, 0..39] of Byte;
  LineBuf: array[0..159] of Byte;
  Y, P, Pos, Count, BlockX: Integer;
  Ctrl, Val: Byte;
  ReadBytes: Word;
begin
  Seek(ImgFile, 0);
  BlockRead(ImgFile, ResWord, 2, ReadBytes);
  BlockRead(ImgFile, RawPal, 32, ReadBytes);
  SetupAtariPalette(RawPal);

  for Y := 0 to 199 do
  begin
    if CheckUserAbort then
    begin
      UserAborted := True;
      Exit;
    end;

    for P := 0 to 3 do
    begin
      Pos := 0;
      while Pos < 40 do
      begin
        BlockRead(ImgFile, Ctrl, 1, ReadBytes);
        if ReadBytes = 0 then Exit;
        if Ctrl = 128 then Continue;
        if Ctrl < 128 then
        begin
          Count := Ctrl + 1;
          if Pos + Count > 40 then Count := 40 - Pos;
          BlockRead(ImgFile, Planes[P, Pos], Count, ReadBytes);
          Inc(Pos, Count);
        end
        else
        begin
          Count := 257 - Ctrl;
          if Pos + Count > 40 then Count := 40 - Pos;
          BlockRead(ImgFile, Val, 1, ReadBytes);
          FillChar(Planes[P, Pos], Count, Val);
          Inc(Pos, Count);
        end;
      end;
    end;

    for BlockX := 0 to 19 do
    begin
      LineBuf[BlockX * 8 + 0] := Planes[0, BlockX * 2];
      LineBuf[BlockX * 8 + 1] := Planes[0, BlockX * 2 + 1];
      LineBuf[BlockX * 8 + 2] := Planes[1, BlockX * 2];
      LineBuf[BlockX * 8 + 3] := Planes[1, BlockX * 2 + 1];
      LineBuf[BlockX * 8 + 4] := Planes[2, BlockX * 2];
      LineBuf[BlockX * 8 + 5] := Planes[2, BlockX * 2 + 1];
      LineBuf[BlockX * 8 + 6] := Planes[3, BlockX * 2];
      LineBuf[BlockX * 8 + 7] := Planes[3, BlockX * 2 + 1];
    end;

    RenderAtariScanline(Y, LineBuf);
  end;
end;

procedure RenderDegasPI2;
var
  ResWord: Word;
  RawPal: array[0..31] of Byte;
  LineBuf: array[0..159] of Byte;
  Y, BlockX, Pix, Off: Integer;
  P0, P1: Word;
  Color: Byte;
  BitMask: Word;
  ScreenX: Integer;
  ReadBytes: Word;
begin
  Seek(ImgFile, 0);
  BlockRead(ImgFile, ResWord, 2, ReadBytes);
  BlockRead(ImgFile, RawPal, 32, ReadBytes);
  SetupAtariPalette(RawPal);

  for Y := 0 to 199 do
  begin
    if CheckUserAbort then
    begin
      UserAborted := True;
      Exit;
    end;
    BlockRead(ImgFile, LineBuf, 160, ReadBytes);
    for BlockX := 0 to 39 do
    begin
      Off := BlockX * 4;
      P0 := (Word(LineBuf[Off + 0]) shl 8) or LineBuf[Off + 1];
      P1 := (Word(LineBuf[Off + 2]) shl 8) or LineBuf[Off + 3];

      for Pix := 0 to 15 do
      begin
        if (Pix and 1) = 0 then
        begin
          BitMask := 1 shl (15 - Pix);
          Color := 0;
          if (P0 and BitMask) <> 0 then Inc(Color, 1);
          if (P1 and BitMask) <> 0 then Inc(Color, 2);

          ScreenX := BlockX * 8 + (Pix shr 1);
          if (TargetMode = $13) and (not IsMono) then
            Mem[$A000:(Y * 320) + ScreenX] := Color
          else
            PutPixelRGB(ScreenX, Y, PaletteBuf[Color * 3 + 0],
              PaletteBuf[Color * 3 + 1], PaletteBuf[Color * 3 + 2]);
        end;
      end;
    end;
  end;
end;

procedure RenderDegasPI3;
var
  ResWord: Word;
  RawPal: array[0..31] of Byte;
  LineBuf: array[0..79] of Byte;
  Y, BlockX, Pix, Off: Integer;
  P0: Word;
  BitMask: Word;
  ScreenX, ScreenY: Integer;
  ReadBytes: Word;
begin
  Seek(ImgFile, 0);
  BlockRead(ImgFile, ResWord, 2, ReadBytes);
  BlockRead(ImgFile, RawPal, 32, ReadBytes);
  SetupAtariPalette(RawPal);

  for Y := 0 to 399 do
  begin
    if CheckUserAbort then
    begin
      UserAborted := True;
      Exit;
    end;
    BlockRead(ImgFile, LineBuf, 80, ReadBytes);
    if (Y and 1) = 0 then
    begin
      ScreenY := Y shr 1;
      for BlockX := 0 to 39 do
      begin
        Off := BlockX * 2;
        P0 := (Word(LineBuf[Off + 0]) shl 8) or LineBuf[Off + 1];

        for Pix := 0 to 15 do
        begin
          if (Pix and 1) = 0 then
          begin
            BitMask := 1 shl (15 - Pix);
            ScreenX := BlockX * 8 + (Pix shr 1);
            if (P0 and BitMask) <> 0 then
            begin
              if (TargetMode = $13) and (not IsMono) then
                Mem[$A000:(ScreenY * 320) + ScreenX] := 1
              else
                PutPixelRGB(ScreenX, ScreenY, PaletteBuf[3], PaletteBuf[4], PaletteBuf[5]);
            end
            else
            begin
              if (TargetMode = $13) and (not IsMono) then
                Mem[$A000:(ScreenY * 320) + ScreenX] := 0
              else
                PutPixelRGB(ScreenX, ScreenY, PaletteBuf[0], PaletteBuf[1], PaletteBuf[2]);
            end;
          end;
        end;
      end;
    end;
  end;
end;

procedure RenderDegasPC2;
var
  ResWord: Word;
  RawPal: array[0..31] of Byte;
  Planes: array[0..1, 0..79] of Byte;
  Y, P, Pos, Count, BlockX, Pix, Off: Integer;
  Ctrl, Val: Byte;
  ReadBytes: Word;
  P0, P1: Word;
  Color: Byte;
  BitMask: Word;
  ScreenX: Integer;
begin
  Seek(ImgFile, 0);
  BlockRead(ImgFile, ResWord, 2, ReadBytes);
  BlockRead(ImgFile, RawPal, 32, ReadBytes);
  SetupAtariPalette(RawPal);

  for Y := 0 to 199 do
  begin
    if CheckUserAbort then
    begin
      UserAborted := True;
      Exit;
    end;

    for P := 0 to 1 do
    begin
      Pos := 0;
      while Pos < 80 do
      begin
        BlockRead(ImgFile, Ctrl, 1, ReadBytes);
        if ReadBytes = 0 then Exit;
        if Ctrl = 128 then Continue;
        if Ctrl < 128 then
        begin
          Count := Ctrl + 1;
          if Pos + Count > 80 then Count := 80 - Pos;
          BlockRead(ImgFile, Planes[P, Pos], Count, ReadBytes);
          Inc(Pos, Count);
        end
        else
        begin
          Count := 257 - Ctrl;
          if Pos + Count > 80 then Count := 80 - Pos;
          BlockRead(ImgFile, Val, 1, ReadBytes);
          FillChar(Planes[P, Pos], Count, Val);
          Inc(Pos, Count);
        end;
      end;
    end;

    for BlockX := 0 to 39 do
    begin
      Off := BlockX * 2;
      P0 := (Word(Planes[0, Off + 0]) shl 8) or Planes[0, Off + 1];
      P1 := (Word(Planes[1, Off + 0]) shl 8) or Planes[1, Off + 1];

      for Pix := 0 to 15 do
      begin
        if (Pix and 1) = 0 then
        begin
          BitMask := 1 shl (15 - Pix);
          Color := 0;
          if (P0 and BitMask) <> 0 then Inc(Color, 1);
          if (P1 and BitMask) <> 0 then Inc(Color, 2);

          ScreenX := BlockX * 8 + (Pix shr 1);
          if (TargetMode = $13) and (not IsMono) then
            Mem[$A000:(Y * 320) + ScreenX] := Color
          else
            PutPixelRGB(ScreenX, Y, PaletteBuf[Color * 3 + 0],
              PaletteBuf[Color * 3 + 1], PaletteBuf[Color * 3 + 2]);
        end;
      end;
    end;
  end;
end;

procedure RenderDegasPC3;
var
  ResWord: Word;
  RawPal: array[0..31] of Byte;
  Plane: array[0..79] of Byte;
  Y, Pos, Count, BlockX, Pix, Off: Integer;
  Ctrl, Val: Byte;
  ReadBytes: Word;
  P0: Word;
  BitMask: Word;
  ScreenX, ScreenY: Integer;
begin
  Seek(ImgFile, 0);
  BlockRead(ImgFile, ResWord, 2, ReadBytes);
  BlockRead(ImgFile, RawPal, 32, ReadBytes);
  SetupAtariPalette(RawPal);

  for Y := 0 to 399 do
  begin
    if CheckUserAbort then
    begin
      UserAborted := True;
      Exit;
    end;

    Pos := 0;
    while Pos < 80 do
    begin
      BlockRead(ImgFile, Ctrl, 1, ReadBytes);
      if ReadBytes = 0 then Exit;
      if Ctrl = 128 then Continue;
      if Ctrl < 128 then
      begin
        Count := Ctrl + 1;
        if Pos + Count > 80 then Count := 80 - Pos;
        BlockRead(ImgFile, Plane[Pos], Count, ReadBytes);
        Inc(Pos, Count);
      end
      else
      begin
        Count := 257 - Ctrl;
        if Pos + Count > 80 then Count := 80 - Pos;
        BlockRead(ImgFile, Val, 1, ReadBytes);
        FillChar(Plane[Pos], Count, Val);
        Inc(Pos, Count);
      end;
    end;

    if (Y and 1) = 0 then
    begin
      ScreenY := Y shr 1;
      for BlockX := 0 to 39 do
      begin
        Off := BlockX * 2;
        P0 := (Word(Plane[Off + 0]) shl 8) or Plane[Off + 1];

        for Pix := 0 to 15 do
        begin
          if (Pix and 1) = 0 then
          begin
            BitMask := 1 shl (15 - Pix);
            ScreenX := BlockX * 8 + (Pix shr 1);
            if (P0 and BitMask) <> 0 then
            begin
              if (TargetMode = $13) and (not IsMono) then
                Mem[$A000:(ScreenY * 320) + ScreenX] := 1
              else
                PutPixelRGB(ScreenX, ScreenY, PaletteBuf[3], PaletteBuf[4], PaletteBuf[5]);
            end
            else
            begin
              if (TargetMode = $13) and (not IsMono) then
                Mem[$A000:(ScreenY * 320) + ScreenX] := 0
              else
                PutPixelRGB(ScreenX, ScreenY, PaletteBuf[0], PaletteBuf[1], PaletteBuf[2]);
            end;
          end;
        end;
      end;
    end;
  end;
end;

procedure RenderArtDirector;
var
  RawPal: array[0..31] of Byte;
  LineBuf: array[0..159] of Byte;
  Y: Integer;
  ReadBytes: Word;
begin
  Seek(ImgFile, 0);
  BlockRead(ImgFile, RawPal, 32, ReadBytes);
  SetupAtariPalette(RawPal);

  for Y := 0 to 199 do
  begin
    if CheckUserAbort then
    begin
      UserAborted := True;
      Exit;
    end;
    BlockRead(ImgFile, LineBuf, 160, ReadBytes);
    RenderAtariScanline(Y, LineBuf);
  end;
end;

procedure RenderDoodle;
var
  LineBuf: array[0..79] of Byte;
  Y, BlockX, Pix, Off: Integer;
  P0: Word;
  BitMask: Word;
  ScreenX, ScreenY: Integer;
  ReadBytes: Word;
begin
  Seek(ImgFile, 0);
  PaletteBuf[0] := 0; PaletteBuf[1] := 0; PaletteBuf[2] := 0;
  PaletteBuf[3] := 255; PaletteBuf[4] := 255; PaletteBuf[5] := 255;
  if (TargetMode = $13) and (not IsMono) then
  begin
    Port[$03C8] := 0;
    Port[$03C9] := 0; Port[$03C9] := 0; Port[$03C9] := 0;
    Port[$03C9] := 63; Port[$03C9] := 63; Port[$03C9] := 63;
  end;

  for Y := 0 to 399 do
  begin
    if CheckUserAbort then
    begin
      UserAborted := True;
      Exit;
    end;
    BlockRead(ImgFile, LineBuf, 80, ReadBytes);
    if (Y and 1) = 0 then
    begin
      ScreenY := Y shr 1;
      for BlockX := 0 to 39 do
      begin
        Off := BlockX * 2;
        P0 := (Word(LineBuf[Off + 0]) shl 8) or LineBuf[Off + 1];

        for Pix := 0 to 15 do
        begin
          if (Pix and 1) = 0 then
          begin
            BitMask := 1 shl (15 - Pix);
            ScreenX := BlockX * 8 + (Pix shr 1);
            if (P0 and BitMask) <> 0 then
            begin
              if (TargetMode = $13) and (not IsMono) then
                Mem[$A000:(ScreenY * 320) + ScreenX] := 1
              else
                PutPixelRGB(ScreenX, ScreenY, 255, 255, 255);
            end
            else
            begin
              if (TargetMode = $13) and (not IsMono) then
                Mem[$A000:(ScreenY * 320) + ScreenX] := 0
              else
                PutPixelRGB(ScreenX, ScreenY, 0, 0, 0);
            end;
          end;
        end;
      end;
    end;
  end;
end;


procedure RenderBMP;
var
  FileHdr: TBitmapFileHeader;
  InfoHdr: TBitmapInfoHeader;
  X, Y: Integer;
  SourceY, SourceX: LongInt;
  RowBytes: LongInt;
  R, G, B: Integer;
  SrcOfs: Word;
  RawColor: array[0..3] of Byte;
  I: Integer;
  ClrCount: Word;
  PalIdx: Byte;
begin
  BlockRead(ImgFile, FileHdr, SizeOf(FileHdr));
  BlockRead(ImgFile, InfoHdr, SizeOf(InfoHdr));

  if (InfoHdr.biBitCount <> 8) and (InfoHdr.biBitCount <> 24) then Exit;

  if InfoHdr.biBitCount = 8 then
  begin
    Seek(ImgFile, 14 + InfoHdr.biSize);
    ClrCount := InfoHdr.biClrUsed;
    if ClrCount = 0 then ClrCount := 256;
    for I := 0 to ClrCount - 1 do
    begin
      BlockRead(ImgFile, RawColor, 4);
      PaletteBuf[I * 3 + 0] := RawColor[2];
      PaletteBuf[I * 3 + 1] := RawColor[1];
      PaletteBuf[I * 3 + 2] := RawColor[0];
    end;

    { Upload the custom palette directly to the VGA hardware DAC }
    if (TargetMode = $13) and (not IsMono) then
    begin
      Port[$03C8] := 0;
      for I := 0 to (ClrCount * 3) - 1 do
        Port[$03C9] := PaletteBuf[I] shr 2; { Shift down 8-bit RGB to 6-bit VGA }
    end;

    RowBytes := ((InfoHdr.biWidth + 3) div 4) * 4;
  end
  else
    RowBytes := ((InfoHdr.biWidth * 3 + 3) div 4) * 4;

  BuildScalingMaps(Word(InfoHdr.biWidth), Word(InfoHdr.biHeight));

  for Y := 0 to 199 do
  begin
    if CheckUserAbort then
    begin
      UserAborted := True;
      Exit;
    end;

    SourceY := (LongInt(Y) * InfoHdr.biHeight) div 200;
    if InfoHdr.biHeight > 0 then
      SourceY := InfoHdr.biHeight - 1 - SourceY;

    Seek(ImgFile, FileHdr.bfOffBits + (SourceY * RowBytes));
    BlockRead(ImgFile, ScanLineBuf, RowBytes);

    for X := 0 to 319 do
    begin
      SourceX := (LongInt(X) * InfoHdr.biWidth) div 320;
      if InfoHdr.biBitCount = 8 then
      begin
        PalIdx := ScanLineBuf[SourceX];
        
        { Fast bypass directly to VGA memory }
        if (TargetMode = $13) and (not IsMono) then
        begin
          if (X < 320) and (Y < 200) then
            Mem[$A000:(Y * 320) + X] := PalIdx;
        end
        else
        begin
          { Fallback for EGA/CGA modes }
          R := PaletteBuf[PalIdx * 3 + 0];
          G := PaletteBuf[PalIdx * 3 + 1];
          B := PaletteBuf[PalIdx * 3 + 2];
          PutPixelRGB(X, Y, R, G, B);
        end;
      end
      else
      begin
        SrcOfs := Word(SourceX) * 3;
        B := ScanLineBuf[SrcOfs];
        G := ScanLineBuf[SrcOfs + 1];
        R := ScanLineBuf[SrcOfs + 2];
        PutPixelRGB(X, Y, R, G, B);
      end;
    end;
  end;
end;

function NextGIFByte: Integer;
var
  ActualRead: Word;
begin
  if StreamDone then
  begin
    NextGIFByte := -1;
    Exit;
  end;
  if BlockPos >= BlockLen then
  begin
    BlockRead(ImgFile, BlockLen, 1, ActualRead);
    if (ActualRead = 0) or (BlockLen = 0) then
    begin
      StreamDone := True;
      NextGIFByte := -1;
      Exit;
    end;
    BlockRead(ImgFile, BlockBuf, BlockLen, ActualRead);
    BlockLen := ActualRead;
    BlockPos := 0;
  end;
  NextGIFByte := BlockBuf[BlockPos];
  Inc(BlockPos);
end;

function NextGIFCode(CodeSize: Integer): Integer;
var
  B: Integer;
begin
  while BitsInBuf < CodeSize do
  begin
    B := NextGIFByte;
    if B = -1 then
    begin
      NextGIFCode := -1;
      Exit;
    end;
    BitBuffer := BitBuffer or (LongInt(B) shl BitsInBuf);
    Inc(BitsInBuf, 8);
  end;
  NextGIFCode := Integer(BitBuffer and ((LongInt(1) shl CodeSize) - 1));
  BitBuffer := BitBuffer shr CodeSize;
  Dec(BitsInBuf, CodeSize);
end;

procedure SkipGIFExt;
var
  ExtCode, ExtLen: Byte;
  Dummy: array[0..255] of Byte;
  ActualRead: Word;
begin
  BlockRead(ImgFile, ExtCode, 1);
  repeat
    BlockRead(ImgFile, ExtLen, 1, ActualRead);
    if (ActualRead > 0) and (ExtLen > 0) then
      BlockRead(ImgFile, Dummy, ExtLen);
  until (ActualRead = 0) or (ExtLen = 0) or Eof(ImgFile);
end;

procedure RenderGIF;
var
  Sig: array[0..5] of Char;
  LSD: TLSD;
  Desc: TImageDesc;
  MinCodeSizeByte: Byte;
  MinCodeSize, CodeSize, ClearCode, EOFCode, Available, MaxCode: Integer;
  Code, OldCode, InCode, FirstChar, StackPtr: Integer;
  CurX, CurY, DestX, DestY: Word;
  BlockType, Pass, PixelVal: Byte;
  NumColors, I: Word;
  Interlaced: Boolean;
begin
  BlockRead(ImgFile, Sig, 6);
  BlockRead(ImgFile, LSD, SizeOf(TLSD));
  if (LSD.PackedFields and $80) <> 0 then
  begin
    NumColors := 1 shl ((LSD.PackedFields and 7) + 1);
    BlockRead(ImgFile, PaletteBuf, NumColors * 3);
    if (TargetMode = $13) and (not IsMono) then
    begin
      Port[$03C8] := 0;
      for I := 0 to (NumColors * 3) - 1 do
        Port[$03C9] := PaletteBuf[I] shr 2;
    end;
  end;

  repeat
    BlockRead(ImgFile, BlockType, 1);
    if BlockType = $21 then SkipGIFExt;
  until (BlockType = $2C) or (BlockType = $3B) or Eof(ImgFile);

  if BlockType <> $2C then Exit;

  BlockRead(ImgFile, Desc, SizeOf(TImageDesc));
  Interlaced := (Desc.PackedFields and $40) <> 0;
  if (Desc.PackedFields and $80) <> 0 then
  begin
    NumColors := 1 shl ((Desc.PackedFields and 7) + 1);
    BlockRead(ImgFile, PaletteBuf, NumColors * 3);
    if (TargetMode = $13) and (not IsMono) then
    begin
      Port[$03C8] := 0;
      for I := 0 to (NumColors * 3) - 1 do
        Port[$03C9] := PaletteBuf[I] shr 2;
    end;
  end;

  BlockRead(ImgFile, MinCodeSizeByte, 1);
  MinCodeSize := MinCodeSizeByte;
  if (MinCodeSize < 2) or (MinCodeSize > 11) then Exit;

  BuildScalingMaps(Desc.Width, Desc.Height);

  ClearCode := 1 shl MinCodeSize;
  EOFCode := ClearCode + 1;
  Available := ClearCode + 2;
  CodeSize := MinCodeSize + 1;
  MaxCode := 1 shl CodeSize;
  OldCode := -1;

  CurX := 0; CurY := 0; Pass := 0; StackPtr := 0;
  BlockLen := 0; BlockPos := 0; BitsInBuf := 0; BitBuffer := 0;
  StreamDone := False;

  while True do
  begin
    Code := NextGIFCode(CodeSize);
    if (Code = -1) or (Code = EOFCode) then Break;

    if Code = ClearCode then
    begin
      CodeSize := MinCodeSize + 1;
      MaxCode := 1 shl CodeSize;
      Available := ClearCode + 2;
      OldCode := -1;
      Continue;
    end;

    if OldCode = -1 then
    begin
      OldCode := Code;
      FirstChar := Code;
      PixelStack[0] := FirstChar;
      StackPtr := 1;
    end
    else
    begin
      InCode := Code;
      if Code >= Available then
      begin
        if StackPtr < 4095 then
        begin
          PixelStack[StackPtr] := FirstChar;
          Inc(StackPtr);
        end;
        Code := OldCode;
      end;

      while (Code >= ClearCode) and (Code < 4096) and (StackPtr < 4095) do
      begin
        PixelStack[StackPtr] := SuffixTable[Code];
        Inc(StackPtr);
        Code := PrefixTable[Code];
      end;

      FirstChar := Code;
      if StackPtr < 4095 then
      begin
        PixelStack[StackPtr] := FirstChar;
        Inc(StackPtr);
      end;

      if Available < 4096 then
      begin
        PrefixTable[Available] := OldCode;
        SuffixTable[Available] := FirstChar;
        Inc(Available);
        if (Available >= MaxCode) and (CodeSize < 12) then
        begin
          Inc(CodeSize);
          MaxCode := 1 shl CodeSize;
        end;
      end;
      OldCode := InCode;
    end;

    while StackPtr > 0 do
    begin
      Dec(StackPtr);
      PixelVal := PixelStack[StackPtr];
      if (CurX < 2048) and (CurY < 2048) then
      begin
        DestX := MapX[CurX];
        DestY := MapY[CurY];
        if (TargetMode = $13) and (not IsMono) then
        begin
          if (DestX < 320) and (DestY < 200) then
            Mem[$A000:(DestY * 320) + DestX] := PixelVal;
        end
        else
        begin
          PutPixelRGB(DestX, DestY,
                      PaletteBuf[PixelVal * 3 + 0],
                      PaletteBuf[PixelVal * 3 + 1],
                      PaletteBuf[PixelVal * 3 + 2]);
        end;
      end;
      Inc(CurX);
      if CurX >= Desc.Width then
      begin
        CurX := 0;
        if CheckUserAbort then
        begin
          UserAborted := True;
          Exit;
        end;

        if not Interlaced then Inc(CurY)
        else
        begin
          Inc(CurY, PassStep[Pass]);
          if (CurY >= Desc.Height) and (Pass < 3) then
          begin
            Inc(Pass);
            CurY := PassStart[Pass];
          end;
        end;
      end;
    end;
  end;
end;

procedure InitCosineTable;
var
  X, U: Integer;
  Cu: Real;
begin
  for U := 0 to 7 do
  begin
    if U = 0 then Cu := 0.70710678 else Cu := 1.0;
    for X := 0 to 7 do
      CTable[X, U] := Round(Cu * 256.0 * Cos((2 * X + 1) * U * 3.14159265 / 16.0));
  end;
end;

function ReadJPEGBitstreamByte: Byte;
var
  B: Byte;
begin
  if JStreamPos >= JStreamLen then
  begin
    BlockRead(ImgFile, JStreamBuf, SizeOf(JStreamBuf), JStreamLen);
    JStreamPos := 0;
    if JStreamLen = 0 then
    begin
      ReadJPEGBitstreamByte := 0;
      Exit;
    end;
  end;
  B := JStreamBuf[JStreamPos];
  Inc(JStreamPos);
  ReadJPEGBitstreamByte := B;
end;

function GetJPEGBit: Integer;
var
  B, NextB: Byte;
begin
  if JBitsLeft = 0 then
  begin
    B := ReadJPEGBitstreamByte;
    if B = $FF then
    begin
      NextB := ReadJPEGBitstreamByte;
      if NextB = 0 then
        B := $FF
      else if (NextB >= $D0) and (NextB <= $D7) then
      begin
        Comps[0].PrevDC := 0;
        Comps[1].PrevDC := 0;
        Comps[2].PrevDC := 0;
        B := ReadJPEGBitstreamByte;
        if B = $FF then ReadJPEGBitstreamByte;
      end;
    end;
    JBitBuf := B;
    JBitsLeft := 8;
  end;
  Dec(JBitsLeft);
  GetJPEGBit := (JBitBuf shr JBitsLeft) and 1;
end;

function GetJPEGBits(Count: Integer): Integer;
var
  Val: Integer;
begin
  Val := 0;
  while Count > 0 do
  begin
    Val := (Val shl 1) or GetJPEGBit;
    Dec(Count);
  end;
  GetJPEGBits := Val;
end;

function ExtendSign(Val, Bits: Integer): Integer;
begin
  if Val < (1 shl (Bits - 1)) then
    ExtendSign := Val - (1 shl Bits) + 1
  else
    ExtendSign := Val;
end;

procedure BuildHuffTable(Tbl: Integer);
var
  I, Code: Integer;
begin
  Code := 0;
  for I := 1 to 16 do
  begin
    if HuffBits[Tbl, I] <> 0 then
    begin
      MinCode[Tbl, I] := Code;
      Code := Code + HuffBits[Tbl, I];
      MaxCode[Tbl, I] := Code - 1;
    end
    else
    begin
      MinCode[Tbl, I] := -1;
      MaxCode[Tbl, I] := -1;
    end;
    Code := Code shl 1;
  end;
end;

function DecodeHuffSymbol(Tbl: Integer): Integer;
var
  L, Code: Integer;
begin
  Code := GetJPEGBit;
  L := 1;
  while (L <= 16) and (Code > MaxCode[Tbl, L]) do
  begin
    Code := (Code shl 1) or GetJPEGBit;
    Inc(L);
  end;
  if L > 16 then DecodeHuffSymbol := 0
  else DecodeHuffSymbol := HuffVal[Tbl, ValPtr[Tbl, L] + (Code - MinCode[Tbl, L])];
end;

procedure DecodeBlock(CompIdx: Integer; var OutBlock: array of Integer);
var
  Coeffs: array[0..63] of Integer;
  Tmp: array[0..63] of LongInt;
  Sum, DCVal: LongInt;
  I, X, Y, U, V, S, R, Bits: Integer;
  DCTbl, ACTbl, QTbl: Integer;
begin
  FillChar(Coeffs, SizeOf(Coeffs), 0);
  DCTbl := Comps[CompIdx].DCTbl;
  ACTbl := Comps[CompIdx].ACTbl;
  QTbl  := Comps[CompIdx].QTIdx;

  S := DecodeHuffSymbol(DCTbl);
  if S > 0 then
  begin
    Bits := GetJPEGBits(S);
    Inc(Comps[CompIdx].PrevDC, ExtendSign(Bits, S));
  end;
  Coeffs[0] := Comps[CompIdx].PrevDC * QTable[QTbl, 0];

  I := 1;
  while I < 64 do
  begin
    S := DecodeHuffSymbol(ACTbl);
    if S = 0 then Break;
    if S = $F0 then Inc(I, 16)
    else
    begin
      R := S shr 4;
      S := S and $0F;
      Inc(I, R);
      if I < 64 then
      begin
        Bits := GetJPEGBits(S);
        Coeffs[ZigZag[I]] := ExtendSign(Bits, S) * QTable[QTbl, I];
      end;
      Inc(I);
    end;
  end;

  for Y := 0 to 7 do
  begin
    if (Coeffs[Y*8+1]=0) and (Coeffs[Y*8+2]=0) and (Coeffs[Y*8+3]=0) and
       (Coeffs[Y*8+4]=0) and (Coeffs[Y*8+5]=0) and (Coeffs[Y*8+6]=0) and
       (Coeffs[Y*8+7]=0) then
    begin
      DCVal := (LongInt(Coeffs[Y*8]) * CTable[0, 0]) div 16;
      for X := 0 to 7 do Tmp[Y*8 + X] := DCVal;
    end
    else
    begin
      for X := 0 to 7 do
      begin
        Sum := 0;
        for U := 0 to 7 do
          if Coeffs[Y*8 + U] <> 0 then
            Inc(Sum, LongInt(Coeffs[Y*8 + U]) * CTable[X, U]);
        Tmp[Y*8 + X] := Sum div 16;
      end;
    end;
  end;

  for X := 0 to 7 do
  begin
    if (Tmp[1*8+X]=0) and (Tmp[2*8+X]=0) and (Tmp[3*8+X]=0) and
       (Tmp[4*8+X]=0) and (Tmp[5*8+X]=0) and (Tmp[6*8+X]=0) and
       (Tmp[7*8+X]=0) then
    begin
      DCVal := ((Tmp[X] * CTable[0, 0] + 8192) div 16384) + 128;
      if DCVal < 0 then DCVal := 0 else if DCVal > 255 then DCVal := 255;
      for Y := 0 to 7 do OutBlock[Y*8 + X] := Integer(DCVal);
    end
    else
    begin
      for Y := 0 to 7 do
      begin
        Sum := 0;
        for V := 0 to 7 do
          Inc(Sum, Tmp[V*8 + X] * CTable[Y, V]);
        DCVal := ((Sum + 8192) div 16384) + 128;
        if DCVal < 0 then DCVal := 0 else if DCVal > 255 then DCVal := 255;
        OutBlock[Y*8 + X] := Integer(DCVal);
      end;
    end;
  end;
end;

procedure RenderJPEG;
var
  Marker, Len: Word;
  B, ScanCount, TblByte, CompId, TableHdr: Byte;
  I, P, MCU_X, MCU_Y, BX, BY, BlkIdx, NumY: Integer;
  YBlock: array[0..3, 0..63] of Integer;
  CbBlock, CrBlock: array[0..63] of Integer;
  Px, Py, ScreenX, ScreenY: Word;
  Lum, Cb, Cr, R, G, Bl: Integer;
  SkipBuf: array[0..255] of Byte;
  ToSkip, MCU_W, MCU_H: Word;
  C: Integer;
  TblId: Byte;
begin
  InitCosineTable;
  JBitsLeft := 0;
  JBitBuf := 0;
  JStreamPos := 0;
  JStreamLen := 0;
  Comps[0].PrevDC := 0;
  Comps[1].PrevDC := 0;
  Comps[2].PrevDC := 0;

  repeat
    BlockRead(ImgFile, B, 1);
    if B = $FF then
    begin
      BlockRead(ImgFile, B, 1);
      Marker := $FF00 or B;
      case Marker of
        $FFDB: { DQT }
          begin
            BlockRead(ImgFile, Len, 2);
            Len := Swap(Len) - 2;
            while Len > 0 do
            begin
              BlockRead(ImgFile, TableHdr, 1);
              TblId := TableHdr and $0F;
              for I := 0 to 63 do
              begin
                BlockRead(ImgFile, B, 1);
                QTable[TblId, I] := B;
              end;
              Dec(Len, 65);
            end;
          end;
        $FFC0: { SOF0 }
          begin
            BlockRead(ImgFile, Len, 2);
            BlockRead(ImgFile, B, 1);
            BlockRead(ImgFile, JHeight, 2);
            JHeight := Swap(JHeight);
            BlockRead(ImgFile, JWidth, 2);
            JWidth := Swap(JWidth);
            BlockRead(ImgFile, B, 1);
            NumComps := B;
            for I := 0 to NumComps - 1 do
            begin
              BlockRead(ImgFile, Comps[I].Id, 1);
              BlockRead(ImgFile, B, 1);
              Comps[I].H := B shr 4;
              Comps[I].V := B and $0F;
              BlockRead(ImgFile, Comps[I].QTIdx, 1);
            end;
          end;
        $FFC4: { DHT }
          begin
            BlockRead(ImgFile, Len, 2);
            Len := Swap(Len) - 2;
            while Len > 0 do
            begin
              BlockRead(ImgFile, B, 1);
              I := ((B and $10) shr 3) or (B and $0F);
              BlockRead(ImgFile, HuffBits[I, 1], 16);
              Dec(Len, 17);

              P := 0;
              for C := 1 to 16 do
              begin
                ValPtr[I, C] := P;
                if HuffBits[I, C] > 0 then
                begin
                  BlockRead(ImgFile, HuffVal[I, P], HuffBits[I, C]);
                  Inc(P, HuffBits[I, C]);
                  Dec(Len, HuffBits[I, C]);
                end;
              end;
              BuildHuffTable(I);
            end;
          end;
        $FFDA: { SOS }
          begin
            BlockRead(ImgFile, Len, 2);
            BlockRead(ImgFile, ScanCount, 1);
            for I := 0 to ScanCount - 1 do
            begin
              BlockRead(ImgFile, CompId, 1);
              BlockRead(ImgFile, TblByte, 1);
              for C := 0 to NumComps - 1 do
                if Comps[C].Id = CompId then
                begin
                  Comps[C].DCTbl := TblByte shr 4;
                  Comps[C].ACTbl := (TblByte and $0F) + 2;
                end;
            end;
            BlockRead(ImgFile, SkipBuf, 3);
            Break;
          end;
        $FFD8: ; { SOI }
        else
          begin
            if (Marker and $FF00 = $FF00) and (Marker <> $FFFF) then
            begin
              BlockRead(ImgFile, Len, 2);
              Len := Swap(Len);
              if Len >= 2 then
              begin
                Dec(Len, 2);
                while Len > 0 do
                begin
                  if Len > SizeOf(SkipBuf) then ToSkip := SizeOf(SkipBuf) else ToSkip := Len;
                  BlockRead(ImgFile, SkipBuf, ToSkip);
                  Dec(Len, ToSkip);
                end;
              end;
            end;
          end;
      end;
    end;
  until Eof(ImgFile);

  BuildScalingMaps(JWidth, JHeight);

  if NumComps = 1 then
  begin
    MCU_W := 8;
    MCU_H := 8;
    NumY := 1;
  end
  else
  begin
    MCU_W := Comps[0].H * 8;
    MCU_H := Comps[0].V * 8;
    NumY := Comps[0].H * Comps[0].V;
  end;

  MCU_Y := 0;
  while MCU_Y < JHeight do
  begin
    MCU_X := 0;
    while MCU_X < JWidth do
    begin
      if CheckUserAbort then
      begin
        UserAborted := True;
        Exit;
      end;

      if NumComps = 1 then
      begin
        DecodeBlock(0, YBlock[0]);
        for BY := 0 to 7 do
          for BX := 0 to 7 do
          begin
            Px := MCU_X + BX;
            Py := MCU_Y + BY;
            if (Px < JWidth) and (Py < JHeight) then
            begin
              ScreenX := MapX[Px];
              ScreenY := MapY[Py];
              Lum := YBlock[0, BY * 8 + BX];
              PutPixelRGB(ScreenX, ScreenY, Lum, Lum, Lum);
            end;
          end;
      end
      else
      begin
        for I := 0 to NumY - 1 do
          DecodeBlock(0, YBlock[I]);
        DecodeBlock(1, CbBlock);
        DecodeBlock(2, CrBlock);

        for BY := 0 to MCU_H - 1 do
          for BX := 0 to MCU_W - 1 do
          begin
            Px := MCU_X + BX;
            Py := MCU_Y + BY;
            if (Px < JWidth) and (Py < JHeight) then
            begin
              ScreenX := MapX[Px];
              ScreenY := MapY[Py];

              if (Comps[0].H = 2) and (Comps[0].V = 2) then
              begin
                BlkIdx := ((BY shr 3) shl 1) + (BX shr 3);
                Lum := YBlock[BlkIdx, (BY and 7) * 8 + (BX and 7)];
                Cb  := CbBlock[(BY shr 1) * 8 + (BX shr 1)] - 128;
                Cr  := CrBlock[(BY shr 1) * 8 + (BX shr 1)] - 128;
              end
              else if (Comps[0].H = 2) and (Comps[0].V = 1) then
              begin
                BlkIdx := BX shr 3;
                Lum := YBlock[BlkIdx, BY * 8 + (BX and 7)];
                Cb  := CbBlock[BY * 8 + (BX shr 1)] - 128;
                Cr  := CrBlock[BY * 8 + (BX shr 1)] - 128;
              end
              else
              begin
                Lum := YBlock[0, BY * 8 + BX];
                Cb  := CbBlock[BY * 8 + BX] - 128;
                Cr  := CrBlock[BY * 8 + BX] - 128;
              end;

              R  := Lum + Integer((LongInt(359) * Cr) div 256);
              G  := Lum - Integer((LongInt(88) * Cb + LongInt(183) * Cr) div 256);
              Bl := Lum + Integer((LongInt(454) * Cb) div 256);

              PutPixelRGB(ScreenX, ScreenY, R, G, Bl);
            end;
          end;
      end;
      Inc(MCU_X, MCU_W);
    end;
    Inc(MCU_Y, MCU_H);
  end;
end;

{ --- Main Program Entry Point --- }

var
  Fmt: TFormat;
  I, C: Integer;
  Param, ParamUpper: string;
  Regs: Registers;
begin
  if ParamCount < 1 then
  begin
    WriteLn('FASTVIEW: Universal 320x200 Viewer (CGA/EGA/VGA)');
    WriteLn('Usage: FASTVIEW <filename> [/VGA | /EGA | /CGA] [/M]');
    Halt(1);
  end;

  FileName := '';
  TargetMode := $00;
  IsMono := False;

  for I := 1 to ParamCount do
  begin
    Param := ParamStr(I);
    ParamUpper := Param;
    
    { Convert parameter to uppercase for safe evaluation }
    for C := 1 to Length(ParamUpper) do 
      ParamUpper[C] := UpCase(ParamUpper[C]);

    if (ParamUpper = '/M') or (ParamUpper = '-M') then
      IsMono := True
    else if (ParamUpper = '/CGA') or (ParamUpper = '-CGA') then
      TargetMode := $04
    else if (ParamUpper = '/EGA') or (ParamUpper = '-EGA') then
      TargetMode := $0D
    else if (ParamUpper = '/VGA') or (ParamUpper = '-VGA') then
      TargetMode := $13
    else if FileName = '' then
      FileName := Param; { Preserve original casing for the file path }
  end;

  if FileName = '' then
  begin
    WriteLn('Error: No input file specified.');
    Halt(1);
  end;

  if TargetMode = $00 then
    TargetMode := AutoDetectAdapter;

  Assign(ImgFile, FileName);
  Reset(ImgFile, 1);
  if IOResult <> 0 then
  begin
    WriteLn('Error: Cannot open file.');
    Halt(1);
  end;

  Fmt := DetectFormat;
  if Fmt = fmtUnknown then
  begin
    Close(ImgFile);
    WriteLn('Error: Unknown or unsupported file format.');
    Halt(1);
  end;

  BuildColorLUTs;
  InitVideo;

  if TargetMode = $13 then
  begin
    if IsMono then
      SetupVGAMonoPalette
    else
      SetupRGB332Palette;
  end;

  UserAborted := False;

  case Fmt of
    fmtBMP: RenderBMP;
    fmtGIF: RenderGIF;
    fmtJPG: RenderJPEG;
    fmtDegasPI1: RenderDegasPI1;
    fmtDegasPI2: RenderDegasPI2;
    fmtDegasPI3: RenderDegasPI3;
    fmtDegasPC1: RenderDegasPC1;
    fmtDegasPC2: RenderDegasPC2;
    fmtDegasPC3: RenderDegasPC3;
    fmtNeoChrome: RenderNeoChrome;
    fmtArtDirector: RenderArtDirector;
    fmtDoodle: RenderDoodle;
  end;

  { Flush any keystrokes before waiting for keypress }
  while (MemW[$0040:$001A] <> MemW[$0040:$001C]) do
  begin
    Regs.AH := $00;
    Intr($16, Regs);
  end;

  { Only wait for a keypress if user didn't abort with Esc }
  if not UserAborted then
    WaitForKey;

  CloseVideo;
  Close(ImgFile);
end.