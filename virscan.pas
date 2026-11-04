unit VirScan;

{$F+,R-,S-,I-,V-,A-}

interface

uses Dos;

type
  PByteArray = ^TByteArray;
  TByteArray = array[0..32767] of Byte;

  TVirusThreatType = (ttNone, ttBootVirus, ttProtector, ttCustomBoot, ttFileVirus);

  TVirusResult = record
    ThreatFound: Boolean;
    ThreatType: TVirusThreatType;
    Name: string[60];
    Description: string[100];
    IsExecutable: Boolean;
    BootSum: Word;
    Offset: Integer;
    CanDisinfect: Boolean;
  end;

{ Core Scanner & Checksum API }
function  CalculateAtariBootChecksum(Buf: Pointer; Size: Integer): Word;
function  ScanBootSectorData(const BootSec: array of Byte; var Res: TVirusResult): Boolean;
function  ScanFileMem(Buf: Pointer; BufLen: Word; const FileName: string; var Res: TVirusResult): Boolean;
function  DisinfectBootData(var BootSec: array of Byte): Boolean;
function  ImmunizeBootData(var BootSec: array of Byte): Boolean;
function  MakePCBootData(var BootSec: array of Byte): Boolean;

implementation

type
  TSigRecord = record
    Name: string[40];
    SigLen: Byte;
    Pattern: array[0..15] of Byte;
    Mask: string[16];
    FixedOff: Integer; { -1 = sliding search, >= 0 = fixed offset }
  end;

const
  NUM_BOOT_SIGS = 30;
  BootSigs: array[0..NUM_BOOT_SIGS - 1] of TSigRecord = (
    { 0: Ghost Boot Virus Standard }
    (Name: 'Ghost Boot Virus (Standard)'; SigLen: 12;
     Pattern: ($43, $F8, $01, $40, $45, $FA, $FF, $F4, $24, $12, $B4, $91, 0,0,0,0);
     Mask: 'xxxxxxxxxxxx'; FixedOff: -1),
    { 1: Ghost Mouse/Tripwire }
    (Name: 'Ghost Boot Virus (Mouse/Tripwire)'; SigLen: 12;
     Pattern: ($06, $B8, $00, $00, $00, $01, $02, $EA, $0C, $B8, $00, $00, 0,0,0,0);
     Mask: 'xxxxxxxxxxxx'; FixedOff: -1),
    { 2: Ghost Generic Reset Vector }
    (Name: 'Ghost Virus (Reset Vector/Resvalid)'; SigLen: 12;
     Pattern: ($20, $3C, $31, $41, $59, $26, $42, $81, $B0, $B8, $04, $26, 0,0,0,0);
     Mask: 'xxxxxxxxxxxx'; FixedOff: -1),
    { 3: Ghost Generic BPB Hook }
    (Name: 'Ghost Virus (BPB Vector Hook)'; SigLen: 10;
     Pattern: ($20, $38, $04, $72, $41, $F8, $02, $E2, $20, $80, 0,0,0,0,0,0);
     Mask: 'xxxxxxxxxx'; FixedOff: -1),
    { 4: Signum Boot Virus }
    (Name: 'Signum Boot Virus'; SigLen: 12;
     Pattern: ($41, $FA, $FF, $C4, $22, $79, $00, $00, $04, $C6, $D3, $FC, 0,0,0,0);
     Mask: 'xxxxxxxxxxxx'; FixedOff: -1),
    { 5: Kobold #1 Virus (KVI) }
    (Name: 'Kobold #1 Boot Virus (KVI)'; SigLen: 8;
     Pattern: ($60, $38, Byte('K'), Byte('O'), Byte('B'), Byte('O'), Byte('L'), Byte('D'), 0,0,0,0,0,0,0,0);
     Mask: 'xxxxxxxx'; FixedOff: 0),
    { 6: Kobold #2 Virus }
    (Name: 'Kobold #2 Virus'; SigLen: 12;
     Pattern: (Byte('K'), Byte('O'), Byte('B'), Byte('O'), Byte('L'), Byte('D'), Byte('#'), Byte('2'),
               Byte(' '), Byte('A'), Byte('K'), Byte('T'), 0,0,0,0);
     Mask: 'xxxxxxxxxxxx'; FixedOff: -1),
    { 7: MAD Virus }
    (Name: 'MAD Virus'; SigLen: 10;
     Pattern: ($48, $E7, $FF, $FE, $41, $FA, $00, $00, $20, $7C, 0,0,0,0,0,0);
     Mask: 'xxxxxx??xx'; FixedOff: -1),
    { 8: MAD Scrolltext }
    (Name: 'MAD Virus (Scrolltext)'; SigLen: 6;
     Pattern: ($E3, $4B, $D5, $3D, $97, $8C, 0,0,0,0,0,0,0,0,0,0);
     Mask: 'xxxxxx'; FixedOff: -1),
    { 9: Green Goblins }
    (Name: 'Green Goblins Virus'; SigLen: 12;
     Pattern: (Byte('G'), Byte('r'), Byte('e'), Byte('e'), Byte('n'), Byte(' '),
               Byte('G'), Byte('o'), Byte('b'), Byte('l'), Byte('i'), Byte('n'), 0,0,0,0);
     Mask: 'xxxxxxxxxxxx'; FixedOff: -1),
    { 10: Medway Boys }
    (Name: 'Medway Boys Boot Virus'; SigLen: 11;
     Pattern: (Byte('M'), Byte('E'), Byte('D'), Byte('W'), Byte('A'), Byte('Y'),
               Byte(' '), Byte('B'), Byte('O'), Byte('Y'), Byte('S'), 0,0,0,0,0);
     Mask: 'xxxxxxxxxxx'; FixedOff: -1),
    { 11: C'est La Vie }
    (Name: 'C''est La Vie Boot Virus'; SigLen: 12;
     Pattern: (Byte('C'), Byte(''''), Byte('E'), Byte('S'), Byte('T'), Byte(' '),
               Byte('L'), Byte('A'), Byte(' '), Byte('V'), Byte('I'), Byte('E'), 0,0,0,0);
     Mask: 'xxxxxxxxxxxx'; FixedOff: -1),
    { 12: NRP Virus }
    (Name: 'NRP Boot Virus (No Real Problem)'; SigLen: 9;
     Pattern: (Byte('N'), Byte('R'), Byte('P'), Byte(' '), Byte('V'), Byte('I'),
               Byte('R'), Byte('U'), Byte('S'), 0,0,0,0,0,0,0);
     Mask: 'xxxxxxxxx'; FixedOff: -1),
    { 13: Anti-Ghost Virus }
    (Name: 'Anti-Ghost Boot Virus'; SigLen: 10;
     Pattern: (Byte('A'), Byte('N'), Byte('T'), Byte('I'), Byte('-'), Byte('G'),
               Byte('H'), Byte('O'), Byte('S'), Byte('T'), 0,0,0,0,0,0);
     Mask: 'xxxxxxxxxx'; FixedOff: -1),
    { 14: Sub-Rosa Virus }
    (Name: 'Sub-Rosa Boot Virus'; SigLen: 8;
     Pattern: (Byte('S'), Byte('U'), Byte('B'), Byte('-'), Byte('R'), Byte('O'),
               Byte('S'), Byte('A'), 0,0,0,0,0,0,0,0);
     Mask: 'xxxxxxxx'; FixedOff: -1),
    { 15: Alcool Virus }
    (Name: 'Alcoolique Boot Virus'; SigLen: 6;
     Pattern: (Byte('A'), Byte('L'), Byte('C'), Byte('O'), Byte('O'), Byte('L'), 0,0,0,0,0,0,0,0,0,0);
     Mask: 'xxxxxx'; FixedOff: -1),
    { 16: Vaxina Virus }
    (Name: 'Vaxina Boot Virus'; SigLen: 6;
     Pattern: (Byte('V'), Byte('A'), Byte('X'), Byte('I'), Byte('N'), Byte('A'), 0,0,0,0,0,0,0,0,0,0);
     Mask: 'xxxxxx'; FixedOff: -1),
    { 17: Cookie Virus }
    (Name: 'Cookie Boot Virus'; SigLen: 16;
     Pattern: (Byte('I'), Byte(' '), Byte('W'), Byte('A'), Byte('N'), Byte('T'), Byte(' '), Byte('A'),
               Byte(' '), Byte('C'), Byte('O'), Byte('O'), Byte('K'), Byte('I'), Byte('E'), Byte('!'));
     Mask: 'xxxxxxxxxxxxxxxx'; FixedOff: -1),
    { 18: ACA Virus }
    (Name: 'ACA Boot Virus'; SigLen: 8;
     Pattern: ($60, $00, $00, $94, Byte('A'), Byte('C'), Byte('A'), $09, 0,0,0,0,0,0,0,0);
     Mask: 'xxxxxxxx'; FixedOff: 0),
    { 19: Zorro Virus }
    (Name: 'Zorro Boot Virus'; SigLen: 12;
     Pattern: ($EB, $34, $90, $03, $60, $18, $4E, $F9, $C7, $11, $D6, $00, 0,0,0,0);
     Mask: 'xxxxxxxxxxxx'; FixedOff: 0),
    { 20: Evil Nick }
    (Name: 'Evil Nick Boot Virus'; SigLen: 12;
     Pattern: (Byte('E'), Byte('V'), Byte('I'), Byte('L'), Byte(' '), Byte('!'),
               Byte(' '), Byte('-'), Byte(' '), Byte('A'), Byte(' '), Byte('G'), 0,0,0,0);
     Mask: 'xxxxxxxxxxxx'; FixedOff: -1),
    { 21: Oli Virus }
    (Name: 'Oli Boot Virus'; SigLen: 9;
     Pattern: (Byte('O'), Byte('L'), Byte('I'), Byte('-'), Byte('V'), Byte('I'),
               Byte('R'), Byte('U'), Byte('S'), 0,0,0,0,0,0,0);
     Mask: 'xxxxxxxxx'; FixedOff: -1),
    { 22: Vire 87 / Muncher }
    (Name: 'Vire 87 Boot Virus'; SigLen: 7;
     Pattern: (Byte('V'), Byte('I'), Byte('R'), Byte('E'), Byte(' '), Byte('8'), Byte('7'), 0,0,0,0,0,0,0,0,0);
     Mask: 'xxxxxxx'; FixedOff: -1),
    { 23: Macumba Virus }
    (Name: 'Macumba Boot Virus'; SigLen: 12;
     Pattern: ($EB, $34, $90, $05, $60, $18, $4E, $F9, $01, $DE, $5C, $00, 0,0,0,0);
     Mask: 'xxxxxxxxxxxx'; FixedOff: 0),
    { 24: Disk-Doctor / Cva }
    (Name: 'Disk-Doctor / Cva Boot Virus'; SigLen: 12;
     Pattern: ($60, $1C, $00, $00, $2F, $08, $20, $79, $00, $00, $04, $C6, 0,0,0,0);
     Mask: 'xxxxxxxxxxxx'; FixedOff: -1),
    { 25: SCA Boot Virus }
    (Name: 'SCA Boot Virus'; SigLen: 9;
     Pattern: (Byte('S'), Byte('C'), Byte('A'), Byte(' '), Byte('V'), Byte('I'),
               Byte('R'), Byte('U'), Byte('S'), 0,0,0,0,0,0,0);
     Mask: 'xxxxxxxxx'; FixedOff: -1),
    { 26: Greenpeace Virus }
    (Name: 'Greenpeace Boot Virus'; SigLen: 10;
     Pattern: ($48, $E7, $FF, $FE, $41, $FA, $00, $4C, $20, $3C, 0,0,0,0,0,0);
     Mask: 'xxxxxxxxxx'; FixedOff: -1),
    { 27: Silly Boot Virus }
    (Name: 'Silly Boot Virus'; SigLen: 10;
     Pattern: ($23, $FC, $00, $00, $00, $00, $00, $00, $04, $2A, 0,0,0,0,0,0);
     Mask: 'xx????xxxx'; FixedOff: -1),
    { 28: Screen Virus }
    (Name: 'Screen Boot Virus'; SigLen: 8;
     Pattern: ($0C, $6C, $E6, $56, $00, $02, $67, $00, 0,0,0,0,0,0,0,0);
     Mask: 'xxxxxxxx'; FixedOff: -1),
    { 29: Pirate Trap }
    (Name: 'Pirate Trap Trojan'; SigLen: 8;
     Pattern: ($4E, $4E, $4E, $4E, $91, $04, $AB, $00, 0,0,0,0,0,0,0,0);
     Mask: 'xxxxxxxx'; FixedOff: 4)
  );

  NUM_FILE_SIGS = 6;
  FileSigs: array[0..NUM_FILE_SIGS - 1] of TSigRecord = (
    (Name: 'Ghost Linkvirus (TOS-Link)'; SigLen: 12;
     Pattern: ($43, $FA, $00, $2E, $20, $51, $22, $50, $20, $7C, $31, $41, 0,0,0,0);
     Mask: 'xxxxxxxxxxxx'; FixedOff: -1),
    (Name: 'Pluto File Virus'; SigLen: 12;
     Pattern: ($20, $3C, $00, $00, $04, $40, $4E, $68, $20, $08, $20, $48, 0,0,0,0);
     Mask: 'xxxxxxxxxxxx'; FixedOff: -1),
    (Name: 'Saddam File Virus'; SigLen: 12;
     Pattern: ($4E, $56, $FF, $F8, $48, $E7, $00, $1C, $2F, $0C, $2E, $88, 0,0,0,0);
     Mask: 'xxxxxxxxxxxx'; FixedOff: -1),
    (Name: 'Byte Bandit Infector'; SigLen: 12;
     Pattern: ($48, $E7, $80, $80, $20, $7C, $00, $00, $04, $72, $22, $50, 0,0,0,0);
     Mask: 'xxxxxxxxxxxx'; FixedOff: -1),
    (Name: 'Hello File Virus'; SigLen: 10;
     Pattern: (Byte('H'), Byte('E'), Byte('L'), Byte('L'), Byte('O'), Byte(' '),
               Byte('V'), Byte('I'), Byte('R'), Byte('U'), 0,0,0,0,0,0);
     Mask: 'xxxxxxxxxx'; FixedOff: -1),
    (Name: 'Twister File Virus'; SigLen: 12;
     Pattern: ($20, $7C, $00, $00, $04, $72, $22, $50, $20, $7C, $00, $00, 0,0,0,0);
     Mask: 'xxxxxxxxxxxx'; FixedOff: -1)
  );

function CalculateAtariBootChecksum(Buf: Pointer; Size: Integer): Word;
var
  BA: PByteArray;
  I: Integer;
  Sum: Word;
begin
  BA := Buf;
  Sum := 0;
  if (BA = nil) or (Size < 512) then
  begin
    CalculateAtariBootChecksum := 0;
    Exit;
  end;
  for I := 0 to 255 do
    Sum := Sum + ((Word(BA^[I * 2]) shl 8) or Word(BA^[I * 2 + 1]));
  CalculateAtariBootChecksum := Sum;
end;

function MatchMasked(const Data: array of Byte; DataOff, DataLen: Integer; const Sig: TSigRecord): Boolean;
var
  I: Integer;
  D, P: Byte;
  M: Char;
begin
  MatchMasked := False;
  if DataOff + Sig.SigLen > DataLen then Exit;
  for I := 0 to Sig.SigLen - 1 do
  begin
    M := Sig.Mask[I + 1];
    if M = '?' then Continue;
    D := Data[DataOff + I];
    P := Sig.Pattern[I];
    if D <> P then Exit;
  end;
  MatchMasked := True;
end;

function FindSig(const Data: array of Byte; DataLen: Integer; const Sig: TSigRecord): Integer;
var
  I, MaxI: Integer;
begin
  FindSig := -1;
  if Sig.FixedOff >= 0 then
  begin
    if MatchMasked(Data, Sig.FixedOff, DataLen, Sig) then FindSig := Sig.FixedOff;
    Exit;
  end;
  MaxI := DataLen - Sig.SigLen;
  for I := 0 to MaxI do
  begin
    if MatchMasked(Data, I, DataLen, Sig) then
    begin
      FindSig := I;
      Exit;
    end;
  end;
end;

function ContainsText(const Data: array of Byte; DataLen: Integer; const S: string): Boolean;
var
  I, J, SLen, MaxI: Integer;
  Match: Boolean;
  C1, C2: Char;
begin
  ContainsText := False;
  SLen := Length(S);
  if (SLen = 0) or (DataLen < SLen) then Exit;
  MaxI := DataLen - SLen;
  for I := 0 to MaxI do
  begin
    Match := True;
    for J := 1 to SLen do
    begin
      C1 := UpCase(Chr(Data[I + J - 1]));
      C2 := UpCase(S[J]);
      if C1 <> C2 then begin Match := False; Break; end;
    end;
    if Match then begin ContainsText := True; Exit; end;
  end;
end;

function ScanBootSectorData(const BootSec: array of Byte; var Res: TVirusResult): Boolean;
var
  I, MatOff: Integer;
  TargetOff: Integer;
  W: Word;
  B0, B1: Byte;
  HasResvalid, HasResvector, HasHdvBpb, HasHdvRw, HasPhystop, HasFlopwr: Boolean;
begin
  ScanBootSectorData := False;
  FillChar(Res, SizeOf(Res), 0);
  Res.ThreatType := ttNone;
  Res.CanDisinfect := True;

  Res.BootSum := CalculateAtariBootChecksum(@BootSec, 512);
  Res.IsExecutable := (Res.BootSum = $1234);

  { 1. Known Anti-Virus Boot Protectors }
  if ContainsText(BootSec, 512, 'SIGNUM VACCINE') or
     ContainsText(BootSec, 512, 'BOOT GUARD') or
     ContainsText(BootSec, 512, 'TS BOOT GUARD') or
     ContainsText(BootSec, 512, 'POV VIRUS DETECTOR') or
     ContainsText(BootSec, 512, 'LGD BOOT PROTECTOR') or
     ContainsText(BootSec, 512, 'ANTI-VIRUS') or
     ContainsText(BootSec, 512, 'CT PUBLIC DOMAIN') or
     ContainsText(BootSec, 512, 'ANARCHY BOOT PROTECTOR') then
  begin
    Res.ThreatFound := False;
    Res.ThreatType := ttProtector;
    Res.Name := 'Anti-Virus Boot Protector';
    Res.Description := 'Resident boot guard / vaccine protecting vectors against virus infections.';
    ScanBootSectorData := True;
    Exit;
  end;

  { 2. Check Database of Specific Atari ST Boot Viruses }
  for I := 0 to NUM_BOOT_SIGS - 1 do
  begin
    MatOff := FindSig(BootSec, 512, BootSigs[I]);
    if MatOff <> -1 then
    begin
      Res.ThreatFound := True;
      Res.ThreatType := ttBootVirus;
      Res.Name := BootSigs[I].Name;
      Res.Description := 'Matched viral signature in sector 0 at offset $' +
        Chr(48 + ((MatOff shr 8) and $F)) + Chr(48 + ((MatOff shr 4) and $F)) + Chr(48 + (MatOff and $F));
      Res.Offset := MatOff;
      ScanBootSectorData := True;
      Exit;
    end;
  end;

  { 3. Benign Dummy Boot Stubs: BRA directly to RTS ($4E $75) or RTS at 0 }
  if (BootSec[0] = $4E) and (BootSec[1] = $75) then
  begin
    Res.ThreatFound := False;
    Res.ThreatType := ttNone;
    Res.Name := 'Benign Dummy Stub (RTS at 0)';
    ScanBootSectorData := False;
    Exit;
  end;
  if BootSec[0] = $60 then
  begin
    if BootSec[1] <> 0 then
      TargetOff := 2 + ShortInt(BootSec[1])
    else
      TargetOff := 4 + Integer((Word(BootSec[2]) shl 8) or Word(BootSec[3]));
    if (TargetOff >= 2) and (TargetOff + 1 < 510) and
       (BootSec[TargetOff] = $4E) and (BootSec[TargetOff + 1] = $75) then
    begin
      Res.ThreatFound := False;
      Res.ThreatType := ttNone;
      Res.Name := 'Benign Dummy Stub (BRA -> RTS)';
      ScanBootSectorData := False;
      Exit;
    end;
  end;

  { 4. Heuristic Behavioral Analysis for Executable Boot Sectors ($1234) }
  if Res.IsExecutable then
  begin
    HasResvalid  := False;
    HasResvector := False;
    HasHdvBpb    := False;
    HasHdvRw     := False;
    HasPhystop   := False;
    HasFlopwr    := False;

    for I := 0 to 507 do
    begin
      if (BootSec[I] = $31) and (BootSec[I + 1] = $41) and
         (BootSec[I + 2] = $59) and (BootSec[I + 3] = $26) then
        HasResvalid := True;
      W := (Word(BootSec[I]) shl 8) or Word(BootSec[I + 1]);
      if (W = $042A) and (I >= 2) then HasResvector := True;
      if (W = $0472) and (I >= 2) then HasHdvBpb := True;
      if (W = $0476) and (I >= 2) then HasHdvRw := True;
      if (W = $042E) and (I >= 2) then HasPhystop := True;
    end;

    for I := 4 to 508 do
    begin
      { Trap #14 ($4E $4E) preceded by MOVE.W #9, -(SP) ($3F $3C $00 $09) }
      if (BootSec[I] = $4E) and (BootSec[I + 1] = $4E) then
      begin
        if (BootSec[I - 4] = $3F) and (BootSec[I - 3] = $3C) and
           (BootSec[I - 2] = $00) and (BootSec[I - 1] = $09) then
          HasFlopwr := True;
      end;
    end;

    if HasResvalid and (HasHdvBpb or HasResvector) and HasPhystop then
    begin
      Res.ThreatFound := True;
      Res.ThreatType := ttBootVirus;
      if HasFlopwr then
        Res.Name := 'Suspicious Boot Virus (Ghost Infector Profile)'
      else
        Res.Name := 'Suspicious Boot Virus (Resident Vector Hijack)';
      Res.Description := 'Survives warm reset, lowers phystop, hooks system disk vectors.';
      ScanBootSectorData := True;
      Exit;
    end
    else if HasHdvBpb and HasFlopwr then
    begin
      Res.ThreatFound := True;
      Res.ThreatType := ttBootVirus;
      Res.Name := 'Suspicious Boot Virus (Replicating Infector)';
      Res.Description := 'Hooks BPB vector and executes floppy sector write routines.';
      ScanBootSectorData := True;
      Exit;
    end
    else
    begin
      { Safe custom game or demo bootloader }
      Res.ThreatFound := False;
      Res.ThreatType := ttCustomBoot;
      Res.Name := 'Custom Executable Bootloader';
      Res.Description := 'Standard bootable game or demo loader with $1234 checksum.';
      ScanBootSectorData := False;
      Exit;
    end;
  end;

  { Non-executable boot sector with no threats }
  Res.ThreatFound := False;
  Res.ThreatType := ttNone;
  Res.Name := 'Standard Non-Bootable Disk';
  Res.Description := 'Clean standard TOS / DOS format boot sector.';
end;

function ScanFileMem(Buf: Pointer; BufLen: Word; const FileName: string; var Res: TVirusResult): Boolean;
var
  BA: PByteArray;
  I, MatOff: Integer;
  UpperExt: string[4];
begin
  ScanFileMem := False;
  FillChar(Res, SizeOf(Res), 0);
  Res.ThreatType := ttNone;

  if (Buf = nil) or (BufLen < 28) then Exit;
  BA := Buf;

  { Check for PRG / TOS executable magic $601A }
  if (BA^[0] <> $60) or (BA^[1] <> $1A) then Exit;

  { Only scan executables }
  UpperExt := '';
  if Length(FileName) >= 4 then
    UpperExt := Copy(FileName, Length(FileName) - 3, 4);
  for I := 1 to Length(UpperExt) do UpperExt[I] := UpCase(UpperExt[I]);
  if (UpperExt <> '.PRG') and (UpperExt <> '.TOS') and (UpperExt <> '.APP') and
     (UpperExt <> '.GTP') and (UpperExt <> '.ACC') then
    Exit;

  for I := 0 to NUM_FILE_SIGS - 1 do
  begin
    MatOff := -1;
    { Slide scan over first 2048 bytes of executable }
    MatOff := FindSig(TByteArray(Buf^), BufLen, FileSigs[I]);
    if MatOff <> -1 then
    begin
      Res.ThreatFound := True;
      Res.ThreatType := ttFileVirus;
      Res.Name := FileSigs[I].Name;
      Res.Description := 'Infected Atari ST executable file (' + FileName + ')';
      Res.Offset := MatOff;
      ScanFileMem := True;
      Exit;
    end;
  end;
end;

function DisinfectBootData(var BootSec: array of Byte): Boolean;
var
  I: Integer;
  CleanMsg: string[12];
begin
  { Patch initial entry branch instruction past BPB geometry block to byte 30 ($1E) }
  BootSec[0] := $60;
  BootSec[1] := $1C;
  BootSec[2] := $00;
  BootSec[3] := $00;

  { Bytes 11..27: BPB geometry is strictly preserved! }

  { Put a safe "RTS" ($4E $75) exit instruction at offset 30 }
  BootSec[30] := $4E;
  BootSec[31] := $75;

  CleanMsg := 'CLEANED DISK';
  for I := 1 to Length(CleanMsg) do
    BootSec[31 + I] := Byte(CleanMsg[I]);

  { Zero out residual payload outside BPB (offsets 44..509) }
  for I := 44 to 509 do
    BootSec[I] := $00;

  { Reset checksum word at sector tail (offsets 510-511) to non-executable 0 }
  BootSec[510] := $00;
  BootSec[511] := $00;

  DisinfectBootData := True;
end;

function ImmunizeBootData(var BootSec: array of Byte): Boolean;
var
  Msg: string[60];
  I: Integer;
  Sum, TargetWord: Word;
begin
  { Patch initial entry branch instruction past BPB geometry block to byte 30 ($1E) }
  BootSec[0] := $60;
  BootSec[1] := $1C;
  BootSec[2] := $00;
  BootSec[3] := $00;

  { Bytes 11..27: BPB geometry is preserved! }

  { Put executable 68000 vaccine code at offset 30 ($1E):
    LEA Msg(PC), A0  ; $41FA $000C (A0 points to offset 30 + 2 + 12 = 44)
    MOVE.L A0, -(SP) ; $2F08
    MOVE.W #9, -(SP) ; $3F3C $0009 (Cconws: print string)
    TRAP #1          ; $4E41
    ADDQ.L #6, SP    ; $5C8F
    RTS              ; $4E75 }
  BootSec[30] := $41; BootSec[31] := $FA; BootSec[32] := $00; BootSec[33] := $0C;
  BootSec[34] := $2F; BootSec[35] := $08;
  BootSec[36] := $3F; BootSec[37] := $3C; BootSec[38] := $00; BootSec[39] := $09;
  BootSec[40] := $4E; BootSec[41] := $41;
  BootSec[42] := $5C; BootSec[43] := $8F;
  BootSec[44] := $4E; BootSec[45] := $75;

  Msg := #13#10 + '[ TS Boot Guard - Disk Protected ]' + #13#10#0;
  for I := 1 to Length(Msg) do
    BootSec[45 + I] := Byte(Msg[I]);

  for I := 46 + Length(Msg) to 509 do
    BootSec[I] := $00;

  BootSec[510] := $00;
  BootSec[511] := $00;

  Sum := 0;
  for I := 0 to 254 do
    Sum := Sum + ((Word(BootSec[I * 2]) shl 8) or Word(BootSec[I * 2 + 1]));

  TargetWord := $1234 - Sum;
  BootSec[510] := Byte((TargetWord shr 8) and $FF);
  BootSec[511] := Byte(TargetWord and $FF);

  ImmunizeBootData := True;
end;

function MakePCBootData(var BootSec: array of Byte): Boolean;
var
  OemStr: string[8];
  I: Integer;
begin
  { 1. Standard x86 Jump instruction: JMP SHORT $3C; NOP }
  BootSec[0] := $EB;
  BootSec[1] := $3C;
  BootSec[2] := $90;

  { 2. Standard DOS OEM Name: MSDOS5.0 }
  OemStr := 'MSDOS5.0';
  for I := 1 to 8 do
    BootSec[2 + I] := Byte(OemStr[I]);

  { BPB parameters at bytes 11..27 preserved! }

  { 3. Ensure Hidden Sectors = 0 for floppy disk }
  BootSec[$1C] := $00;
  BootSec[$1D] := $00;

  { 4. Extended BPB: Physical Drive $00, Extended Signature $29, Volume ID, FAT12 type }
  BootSec[$24] := $00; { Physical drive 0 }
  BootSec[$25] := $00; { Reserved }
  BootSec[$26] := $29; { Extended boot signature }
  BootSec[$27] := $78; BootSec[$28] := $56; BootSec[$29] := $34; BootSec[$2A] := $12; { Serial }

  { Volume label: NO NAME }
  for I := 0 to 10 do BootSec[$2B + I] := Byte(' ');
  BootSec[$2B] := Byte('N'); BootSec[$2C] := Byte('O'); BootSec[$2D] := Byte(' ');
  BootSec[$2E] := Byte('N'); BootSec[$2F] := Byte('A'); BootSec[$30] := Byte('M'); BootSec[$31] := Byte('E');

  { File system type: FAT12 }
  BootSec[$36] := Byte('F'); BootSec[$37] := Byte('A'); BootSec[$38] := Byte('T');
  BootSec[$39] := Byte('1'); BootSec[$3A] := Byte('2');
  BootSec[$3B] := Byte(' '); BootSec[$3C] := Byte(' '); BootSec[$3D] := Byte(' ');

  { 5. Standard PC x86 Boot Sector Signature at tail: $55, $AA }
  BootSec[510] := $55;
  BootSec[511] := $AA;

  MakePCBootData := True;
end;

end.
