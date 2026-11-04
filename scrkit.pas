{===========================================================================}
{   SCRKIT.PAS - Low-level BIOS / VRAM / Mouse routines for STIMAGE DOS        }
{   Turbo Pascal 7.0 Real-Mode Compatible                                      }
{===========================================================================}
unit ScrKit;

{$R-,S-,I-,V-,A-}

interface

uses Dos;

const
  EVENT_NONE  = 0;
  EVENT_KEY   = 1;
  EVENT_CLICK = 2;

type
  PPopupSave = ^TPopupSave;
  TPopupSave = array[0..1999] of Word;

var
  { Direct VRAM access at $B800:0000 (Color Text Mode 80x25) }
  VRAMW: array[0..1999] of Word absolute $B800:0000;

  { Mouse Driver State (Int 33h) }
  MouseInstalled: Boolean;
  MouseVisible: Boolean;
  MouseBtnCount: Integer;
  LastClickX, LastClickY: Integer;
  LastClickTime: LongInt;
  LastLeftDown: Boolean;

procedure SetCursorPos(X, Y: Integer);
procedure HideCursor;
procedure ShowCursor;
function  ReadKeyBIOS(var ScanCode: Byte): Char;
function  KeyWaiting: Boolean;
function  MouseInit: Boolean;
procedure MouseShow;
procedure MouseHide;
procedure MouseGetStatus(var X, Y: Integer; var LeftBtn, RightBtn: Boolean);
procedure IdleCPU;
function  PollMouse(var ClickX, ClickY: Integer; var DoubleClick: Boolean): Boolean;
function  GetInputEvent(var Ch: Char; var Scan: Byte; var MouseX, MouseY: Integer;
  var DoubleClick: Boolean): Integer;
procedure WriteCell(X, Y: Integer; C: Char; Attr: Byte);
procedure WriteStr(X, Y: Integer; const S: string; Attr: Byte);
procedure FillBox(X1, Y1, X2, Y2: Integer; C: Char; Attr: Byte);
procedure DrawFrame(X1, Y1, X2, Y2: Integer; Attr: Byte; const Title: string);
function  SaveArea(X1, Y1, X2, Y2: Integer): PPopupSave;
procedure RestoreArea(X1, Y1, X2, Y2: Integer; P: PPopupSave);
procedure PromptInput(X, Y: Integer; var S: string; MaxLen: Integer);
procedure SafeExec(const Prog, Params: string);
procedure ShowHelpModal;
procedure ShowAboutModal;

implementation

procedure SetCursorPos(X, Y: Integer);
var
  Regs: Registers;
begin
  Regs.AH := $02;
  Regs.BH := 0;
  Regs.DH := Y;
  Regs.DL := X;
  Intr($10, Regs);
end;

procedure HideCursor;
var
  Regs: Registers;
begin
  Regs.AH := $01;
  Regs.CH := $20;
  Regs.CL := $00;
  Intr($10, Regs);
end;

procedure ShowCursor;
var
  Regs: Registers;
begin
  Regs.AH := $01;
  Regs.CH := 6;
  Regs.CL := 7;
  Intr($10, Regs);
end;

function ReadKeyBIOS(var ScanCode: Byte): Char;
var
  Regs: Registers;
begin
  Regs.AH := $00;
  Intr($16, Regs);
  ScanCode := Regs.AH;
  ReadKeyBIOS := Chr(Regs.AL);
end;

function KeyWaiting: Boolean;
var
  Regs: Registers;
begin
  Regs.AH := $01;
  Intr($16, Regs);
  KeyWaiting := (Regs.Flags and $40) = 0;
end;

function MouseInit: Boolean;
var
  Regs: Registers;
begin
  Regs.AX := 0;
  Intr($33, Regs);
  MouseInstalled := (Regs.AX = $FFFF);
  if MouseInstalled then
    MouseBtnCount := Regs.BX
  else
    MouseBtnCount := 0;
  MouseVisible := False;
  LastLeftDown := False;
  LastClickTime := 0;
  LastClickX := -1;
  LastClickY := -1;
  MouseInit := MouseInstalled;
end;

procedure MouseShow;
var
  Regs: Registers;
begin
  if MouseInstalled and (not MouseVisible) then
  begin
    Regs.AX := 1;
    Intr($33, Regs);
    MouseVisible := True;
  end;
end;

procedure MouseHide;
var
  Regs: Registers;
begin
  if MouseInstalled and MouseVisible then
  begin
    Regs.AX := 2;
    Intr($33, Regs);
    MouseVisible := False;
  end;
end;

procedure MouseGetStatus(var X, Y: Integer; var LeftBtn, RightBtn: Boolean);
var
  Regs: Registers;
begin
  if not MouseInstalled then
  begin
    X := 0; Y := 0; LeftBtn := False; RightBtn := False;
    Exit;
  end;
  Regs.AX := 3;
  Intr($33, Regs);
  X := Regs.CX div 8;
  Y := Regs.DX div 8;
  LeftBtn := (Regs.BX and 1) <> 0;
  RightBtn := (Regs.BX and 2) <> 0;
end;

procedure IdleCPU;
var
  Regs: Registers;
begin
  Regs.AX := $1680;
  Intr($2F, Regs);
end;

function PollMouse(var ClickX, ClickY: Integer; var DoubleClick: Boolean): Boolean;
var
  X, Y: Integer;
  LeftBtn, RightBtn: Boolean;
  NowTicks: LongInt;
begin
  PollMouse := False;
  DoubleClick := False;
  if not MouseInstalled then Exit;

  MouseGetStatus(X, Y, LeftBtn, RightBtn);
  if LeftBtn and (not LastLeftDown) then
  begin
    ClickX := X;
    ClickY := Y;
    NowTicks := MemL[$0040:$006C];
    if (ClickX = LastClickX) and (ClickY = LastClickY) and (NowTicks - LastClickTime <= 8) then
    begin
      DoubleClick := True;
      LastClickTime := 0;
    end
    else
    begin
      LastClickX := ClickX;
      LastClickY := ClickY;
      LastClickTime := NowTicks;
    end;
    PollMouse := True;
  end;
  LastLeftDown := LeftBtn;
end;

function GetInputEvent(var Ch: Char; var Scan: Byte; var MouseX, MouseY: Integer;
  var DoubleClick: Boolean): Integer;
begin
  repeat
    if KeyWaiting then
    begin
      Ch := ReadKeyBIOS(Scan);
      GetInputEvent := EVENT_KEY;
      Exit;
    end;
    if MouseInstalled then
    begin
      if PollMouse(MouseX, MouseY, DoubleClick) then
      begin
        GetInputEvent := EVENT_CLICK;
        Exit;
      end;
    end;
    IdleCPU;
  until False;
end;

procedure WriteCell(X, Y: Integer; C: Char; Attr: Byte);
begin
  if (X >= 0) and (X <= 79) and (Y >= 0) and (Y <= 24) then
    VRAMW[Y * 80 + X] := (Word(Attr) shl 8) or Ord(C);
end;

procedure WriteStr(X, Y: Integer; const S: string; Attr: Byte);
var
  I, First, Last, Ofs: Integer;
  Hi: Word;
begin
  if (Y < 0) or (Y > 24) or (X > 79) then Exit;
  First := 1;
  Last := Length(S);
  if X < 0 then
  begin
    First := 1 - X;
    X := 0;
  end;
  if First > Last then Exit;
  if X + (Last - First + 1) > 80 then
    Last := First + (79 - X);
  Hi := Word(Attr) shl 8;
  Ofs := Y * 80 + X;
  for I := First to Last do
  begin
    VRAMW[Ofs] := Hi or Ord(S[I]);
    Inc(Ofs);
  end;
end;

procedure FillBox(X1, Y1, X2, Y2: Integer; C: Char; Attr: Byte);
var
  X, Y, Ofs: Integer;
  Cell: Word;
begin
  if X1 < 0 then X1 := 0;
  if Y1 < 0 then Y1 := 0;
  if X2 > 79 then X2 := 79;
  if Y2 > 24 then Y2 := 24;
  Cell := (Word(Attr) shl 8) or Ord(C);
  for Y := Y1 to Y2 do
  begin
    Ofs := Y * 80 + X1;
    for X := X1 to X2 do
    begin
      VRAMW[Ofs] := Cell;
      Inc(Ofs);
    end;
  end;
end;

procedure DrawFrame(X1, Y1, X2, Y2: Integer; Attr: Byte; const Title: string);
var
  X, Y: Integer;
  TStr: string;
begin
  WriteCell(X1, Y1, #218, Attr); { Top-Left + }
  WriteCell(X2, Y1, #191, Attr); { Top-Right + }
  WriteCell(X1, Y2, #192, Attr); { Bottom-Left + }
  WriteCell(X2, Y2, #217, Attr); { Bottom-Right + }

  for X := X1 + 1 to X2 - 1 do
  begin
    WriteCell(X, Y1, #196, Attr);
    WriteCell(X, Y2, #196, Attr);
  end;
  for Y := Y1 + 1 to Y2 - 1 do
  begin
    WriteCell(X1, Y, #179, Attr);
    WriteCell(X2, Y, #179, Attr);
  end;

  if Title <> '' then
  begin
    TStr := ' ' + Title + ' ';
    if Length(TStr) > (X2 - X1 - 2) then
      TStr := Copy(TStr, 1, X2 - X1 - 2);
    WriteStr(X1 + 2, Y1, TStr, Attr);
  end;
end;

function SaveArea(X1, Y1, X2, Y2: Integer): PPopupSave;
var
  P: PPopupSave;
  X, Y, Idx: Integer;
begin
  New(P);
  Idx := 0;
  for Y := Y1 to Y2 do
    for X := X1 to X2 do
    begin
      P^[Idx] := VRAMW[Y * 80 + X];
      Inc(Idx);
    end;
  SaveArea := P;
end;

procedure RestoreArea(X1, Y1, X2, Y2: Integer; P: PPopupSave);
var
  X, Y, Idx: Integer;
begin
  if P = nil then Exit;
  Idx := 0;
  for Y := Y1 to Y2 do
    for X := X1 to X2 do
    begin
      VRAMW[Y * 80 + X] := P^[Idx];
      Inc(Idx);
    end;
  Dispose(P);
end;

procedure PromptInput(X, Y: Integer; var S: string; MaxLen: Integer);
var
  Ch: Char;
  Scan: Byte;
  Disp: string;
begin
  repeat
    Disp := S;
    while Length(Disp) < MaxLen do
      Disp := Disp + ' ';
    WriteStr(X, Y, Disp, $1E);
    if Length(S) < MaxLen then
      WriteCell(X + Length(S), Y, '_', $1F);

    Ch := ReadKeyBIOS(Scan);
    if Ch = #27 then
    begin
      S := '';
      Exit;
    end
    else if Ch = #13 then
    begin
      Exit;
    end
    else if Ch = #8 then
    begin
      if Length(S) > 0 then
        S[0] := Chr(Length(S) - 1);
    end
    else if (Ch >= #32) and (Ch <= #126) then
    begin
      if Length(S) < MaxLen then
      begin
        Ch := UpCase(Ch);
        S := S + Ch;
      end;
    end;
  until False;
end;

procedure SafeExec(const Prog, Params: string);
var
  Regs: Registers;
  OrigHeapEnd: Word;
  ShrunkParas: Word;
  CmdTail: string;
begin
  OrigHeapEnd := Seg(HeapEnd^);
  ShrunkParas := Seg(HeapPtr^) - PrefixSeg + 64;

  Regs.AH := $4A;
  Regs.ES := PrefixSeg;
  Regs.BX := ShrunkParas;
  MsDos(Regs);

  CmdTail := Params;
  if (CmdTail <> '') and (CmdTail[1] <> ' ') then
    CmdTail := ' ' + CmdTail;

  SwapVectors;
  Exec(Prog, CmdTail);
  SwapVectors;

  Regs.AH := $4A;
  Regs.ES := PrefixSeg;
  Regs.BX := OrigHeapEnd - PrefixSeg;
  MsDos(Regs);
end;

procedure ShowHelpModal;
var
  Scan: Byte;
  Saved: PPopupSave;
begin
  Saved := SaveArea(6, 3, 74, 22);
  FillBox(6, 3, 74, 22, ' ', $1F);
  DrawFrame(6, 3, 74, 22, $1B, 'STIMAGE for DOS - Quick Help');

  WriteStr(9, 5,  'Navigation & Menus:', $74);
  WriteStr(11, 6, 'F10 / Alt+F/I/V/H : Drop-down menus on top bar', $1F);
  WriteStr(11, 7, 'Up/Down/PgUp/PgDn : Browse file list', $1F);
  WriteStr(11, 8, 'Enter / Backspace : Enter folder / Return to parent', $1F);

  WriteStr(9, 10, 'File & Folder Operations:', $74);
  WriteStr(11, 11, 'O : Open Image (.ST/.MSA/.DIM/.ZIP)   F5 : Extract File', $1F);
  WriteStr(11, 12, 'I : Import DOS File to Image          F7 : Create Subfolder', $1F);
  WriteStr(11, 13, 'Alt+R : Rename File/Folder            Alt+A : Change Attributes', $1F);
  WriteStr(11, 14, 'F8 : Delete File/Folder               U : Undelete (*d*) File', $1F);
  WriteStr(11, 15, 'Z : Extract All as ZIP                P : Depack & Extract', $1F);

  WriteStr(9, 17, 'Disk Tools & Viewers:', $74);
  WriteStr(11, 18, 'F : Search Files (Wildcards)          X : Export Catalog (TXT/CSV)', $1F);
  WriteStr(11, 19, 'B : Boot Sector Hex                   S : Virus Scanner', $1F);
  WriteStr(11, 20, 'M / F6 : Visual Cluster Map           V / Enter : File Viewer', $1F);

  WriteStr(24, 21, 'Press any key to close help...', $74);
  ReadKeyBIOS(Scan);
  RestoreArea(6, 3, 74, 22, Saved);
end;

procedure ShowAboutModal;
var
  Scan: Byte;
  Saved: PPopupSave;
begin
  Saved := SaveArea(15, 6, 65, 18);
  FillBox(15, 6, 65, 18, ' ', $1F);
  DrawFrame(15, 6, 65, 18, $1B, 'About STIMAGE for DOS');

  WriteStr(20, 8,  'STIMAGE for MS-DOS v2.1', $74);
  WriteStr(18, 10, 'Atari ST Floppy Disk Image Manager', $1F);
  WriteStr(18, 11, 'Real-Mode 16-bit DOS Application', $1F);
  WriteStr(18, 13, '(C) 2026 Fredrik / Antigravity Project', $1F);
  WriteStr(18, 14, 'Supports: .ST, .MSA, .DIM, .ZIP Images', $1F);

  WriteStr(24, 16, 'Press any key to return...', $74);
  ReadKeyBIOS(Scan);
  RestoreArea(15, 6, 65, 18, Saved);
end;

end.
