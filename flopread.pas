{===========================================================================}
{   FLOPREAD.PAS - Create disk image from a physical floppy (BIOS Int 13h)     }
{   Turbo Pascal 7.0 Real-Mode Compatible                                      }
{===========================================================================}
unit FlopRead;

{$R-,S-,I-,V-,A-}

interface

{ Shows the dialog, reads the floppy into OutName. Returns True when an image was
  written (dialog stays visible); TotalSec/BadSecs describe the result. }
function FloppyReadDialog(var OutName: string; var Fit720: Boolean;
  var TotalSec, BadSecs: Word): Boolean;
{ Shows the final result box and closes the dialog }
procedure FloppyReadResult(const OutName: string; BadSecs: Word; const Msg: string; Opened: Boolean);

implementation

uses ScrKit, DiskTool;

const
  ATTR_NORMAL    = $1F;
  ATTR_STATUS    = $17;
  ATTR_DIALOG_BG = $70;
  ATTR_DIALOG_BD = $7F;
  ATTR_DIALOG_HL = $74;
  ATTR_DIALOG_OK = $72;
  ATTR_MENU_SEL  = $30;
  KEY_LEFT       = $4B;
  KEY_RIGHT      = $4D;
  KEY_F10        = $44;
  KEY_TAB        = $0F;

var
  Saved: PPopupSave;
  SecDone: Word;

function Num(V: LongInt): string;
var
  S: string;
begin
  Str(V, S);
  Num := S;
end;

procedure CloseDialog;
begin
  MouseHide;
  RestoreArea(6, 4, 73, 20, Saved);
  MouseShow;
end;

procedure WaitKey;
var
  Ch: Char;
  Scan: Byte;
  MX, MY: Integer;
  Dbl: Boolean;
begin
  WriteStr(11, 16, 'Press any key or click to return...', ATTR_DIALOG_HL);
  MouseShow;
  GetInputEvent(Ch, Scan, MX, MY, Dbl);
end;

procedure ErrorBox(const Title, L1, L2: string);
begin
  MouseHide;
  FillBox(8, 7, 71, 18, ' ', ATTR_DIALOG_BG);
  DrawFrame(8, 7, 71, 18, ATTR_DIALOG_BD, Title);
  WriteStr(11, 10, L1, ATTR_NORMAL);
  WriteStr(11, 12, L2, ATTR_DIALOG_BG);
  WaitKey;
  CloseDialog;
end;

function FloppyReadDialog(var OutName: string; var Fit720: Boolean;
  var TotalSec, BadSecs: Word): Boolean;
var
  ActiveBtn: Integer;
  DriveNum: Byte;
  DriveLetter: Char;
  Buf: Pointer;
  Sides, SPT, Tracks: Word;
  Status: Byte;
  Cyl, Head: Word;
  Aborted, Failed, Exists: Boolean;
  Percent, BarLen, J: Integer;
  BarStr: string[26];
  OutF: file;
  Ch: Char;
  Scan: Byte;
  MX, MY: Integer;
  Dbl: Boolean;
  Event: Integer;

  procedure KillOut;
  begin
    Close(OutF);
    if IOResult <> 0 then ;
    Assign(OutF, OutName);
    Erase(OutF);
    if IOResult <> 0 then ;
  end;

begin
  FloppyReadDialog := False;
  DriveNum := 0;
  Fit720 := False;
  OutName := 'FLOPPY.ST';

  Saved := SaveArea(6, 4, 73, 20);
  ActiveBtn := 0;
  repeat
    MouseHide;
    FillBox(6, 4, 73, 20, ' ', ATTR_DIALOG_BG);
    DrawFrame(6, 4, 73, 20, ATTR_DIALOG_BD, ' Create Image from Physical Floppy Disk ');
    if DriveNum = 0 then DriveLetter := 'A' else DriveLetter := 'B';

    WriteStr(9, 7, 'Source Drive:  [< Drive ' + DriveLetter + ': (3.5") >]  (A/B, Arrows, Click)', ATTR_DIALOG_HL);
    WriteStr(9, 9, 'Output Image:  ' + OutName + '                                        ', ATTR_DIALOG_BG);
    WriteStr(55, 9, '(N = edit)', ATTR_DIALOG_BG);
    if Fit720 then
      WriteStr(9, 11, 'Fit in 720K:   [< YES >]  (repack if larger than 720 KB, R/Click)  ', ATTR_DIALOG_OK)
    else
      WriteStr(9, 11, 'Fit in 720K:   [< NO  >]  (keep disk as-is, R/Click)               ', ATTR_DIALOG_BG);
    WriteStr(9, 13, 'Insert the diskette to read. Geometry is detected from the boot', ATTR_DIALOG_BG);
    WriteStr(9, 14, 'sector (BPB). Unreadable sectors are zero-filled and reported.', ATTR_DIALOG_BG);
    if ActiveBtn = 0 then
    begin
      WriteStr(14, 16, '[  START READ (L/Enter)  ]', ATTR_MENU_SEL);
      WriteStr(44, 16, '[  CANCEL (Esc)  ]', ATTR_DIALOG_HL);
    end
    else
    begin
      WriteStr(14, 16, '[  START READ (L/Enter)  ]', ATTR_DIALOG_HL);
      WriteStr(44, 16, '[  CANCEL (Esc)  ]', ATTR_MENU_SEL);
    end;
    WriteStr(9, 18, 'Uses BIOS Int 13h raw track reading with error retries.', ATTR_STATUS);
    MouseShow;

    Event := GetInputEvent(Ch, Scan, MX, MY, Dbl);
    if Event = EVENT_KEY then
    begin
      if (Ch = #27) or (Scan = KEY_F10) then begin CloseDialog; Exit; end;
      if (Ch = #9) or (Scan = KEY_TAB) then ActiveBtn := 1 - ActiveBtn;
      if UpCase(Ch) = 'A' then DriveNum := 0;
      if UpCase(Ch) = 'B' then DriveNum := 1;
      if (Scan = KEY_LEFT) or (Scan = KEY_RIGHT) then ActiveBtn := 1 - ActiveBtn;
      if UpCase(Ch) = 'R' then Fit720 := not Fit720;
      if Ch = ' ' then
      begin
        if ActiveBtn = 1 then begin CloseDialog; Exit; end
        else Fit720 := not Fit720;
      end;
      if UpCase(Ch) = 'N' then
      begin
        PromptInput(24, 9, OutName, 30);
        if OutName = '' then OutName := 'FLOPPY.ST';
      end;
      if Ch = #13 then
      begin
        if ActiveBtn = 1 then begin CloseDialog; Exit; end
        else Break;
      end;
      if UpCase(Ch) = 'L' then begin ActiveBtn := 0; Break; end;
    end
    else if Event = EVENT_CLICK then
    begin
      if (MX < 6) or (MX > 73) or (MY < 4) or (MY > 20) then
      begin
        CloseDialog;
        Exit;
      end
      else if MY = 7 then DriveNum := 1 - DriveNum
      else if MY = 9 then
      begin
        PromptInput(24, 9, OutName, 30);
        if OutName = '' then OutName := 'FLOPPY.ST';
      end
      else if MY = 11 then Fit720 := not Fit720
      else if (MY = 16) and (MX >= 14) and (MX <= 40) then
      begin
        ActiveBtn := 0;
        Break;
      end
      else if (MY = 16) and (MX >= 44) and (MX <= 62) then
      begin
        ActiveBtn := 1;
        CloseDialog;
        Exit;
      end;
    end;
  until False;

  { Overwrite confirmation }
  Assign(OutF, OutName);
  Reset(OutF, 1);
  Exists := (IOResult = 0);
  if Exists then begin Close(OutF); if IOResult <> 0 then ; end;
  if Exists then
  begin
    ActiveBtn := 1;
    repeat
      MouseHide;
      WriteStr(9, 15, 'File exists! Overwrite? ', ATTR_NORMAL);
      if ActiveBtn = 0 then
      begin
        WriteStr(34, 15, '[  YES  ]', ATTR_MENU_SEL);
        WriteStr(45, 15, '[ Cancel ]', ATTR_DIALOG_HL);
      end
      else
      begin
        WriteStr(34, 15, '[  YES  ]', ATTR_DIALOG_HL);
        WriteStr(45, 15, '[ Cancel ]', ATTR_MENU_SEL);
      end;
      MouseShow;
      Event := GetInputEvent(Ch, Scan, MX, MY, Dbl);
      if Event = EVENT_KEY then
      begin
        if (Ch = #9) or (Scan = KEY_TAB) or (Scan = KEY_LEFT) or (Scan = KEY_RIGHT) then
          ActiveBtn := 1 - ActiveBtn
        else if (Ch = #13) then
        begin
          if ActiveBtn = 0 then Break else begin CloseDialog; Exit; end;
        end
        else if UpCase(Ch) = 'Y' then begin ActiveBtn := 0; Break; end
        else if (UpCase(Ch) = 'N') or (Ch = #27) or (Scan = KEY_F10) then begin CloseDialog; Exit; end;
      end
      else if Event = EVENT_CLICK then
      begin
        if (MY = 15) and (MX >= 34) and (MX <= 43) then begin ActiveBtn := 0; Break; end
        else if (MY = 15) and (MX >= 45) and (MX <= 55) then begin CloseDialog; Exit; end;
      end;
    until False;
  end;

  Buf := FloppyBufAlloc;
  if Buf = nil then
  begin
    ErrorBox(' Error ', 'Not enough memory for the track buffer!', '');
    Exit;
  end;

  MouseHide;
  FillBox(8, 7, 71, 18, ' ', ATTR_DIALOG_BG);
  DrawFrame(8, 7, 71, 18, ATTR_DIALOG_BD, ' Reading from Drive ' + DriveLetter + ': ... ');
  WriteStr(11, 9, 'Resetting drive and reading boot sector...', ATTR_DIALOG_HL);
  MouseShow;

  if not FloppyDetectGeometry(DriveNum, Buf, Sides, SPT, Tracks, TotalSec, Status) then
  begin
    FloppyBufFree;
    ErrorBox(' Error ', 'Cannot read Drive ' + DriveLetter + ': ' + Copy(BiosDiskErrorStr(Status), 1, 36),
      'Check that a formatted diskette is inserted.');
    Exit;
  end;

  Assign(OutF, OutName);
  Rewrite(OutF, 1);
  if IOResult <> 0 then
  begin
    FloppyBufFree;
    ErrorBox(' Error ', 'Cannot create output file ' + Copy(OutName, 1, 30), '');
    Exit;
  end;

  MouseHide;
  WriteStr(11, 10, 'Geometry: ' + Num(Tracks) + ' Trk, ' + Num(Sides) + ' Sides, ' +
    Num(SPT) + ' Sec/Trk (' + Num(LongInt(TotalSec) div 2) + ' KB)       ', ATTR_DIALOG_BG);
  MouseShow;

  SecDone := 0;
  BadSecs := 0;
  Aborted := False;
  Failed := False;
  for Cyl := 0 to Tracks - 1 do
  begin
    for Head := 0 to Sides - 1 do
    begin
      MouseHide;
      WriteStr(11, 9, 'Reading Cylinder: ' + Num(Cyl) + '/' + Num(Tracks - 1) +
        '  Head: ' + Num(Head) + '/' + Num(Sides - 1) + '      ', ATTR_DIALOG_HL);
      MouseShow;

      Inc(BadSecs, FloppyReadTrack(DriveNum, Head, Cyl, SPT, Buf));
      BlockWrite(OutF, Buf^, SPT * 512);
      if IOResult <> 0 then
      begin
        Failed := True;
        Break;
      end;

      Inc(SecDone, SPT);
      Percent := Integer((LongInt(SecDone) * 100) div TotalSec);
      BarLen := (Percent * 20) div 100;
      BarStr := '[';
      for J := 1 to 20 do
        if J <= BarLen then BarStr := BarStr + #219 else BarStr := BarStr + #176;
      BarStr := BarStr + '] ' + Num(Percent) + '%';
      MouseHide;
      WriteStr(11, 12, 'Progress: ' + BarStr + ' (' + Num(SecDone) + '/' + Num(TotalSec) + ' sec)  ',
        ATTR_DIALOG_BG);
      if BadSecs > 0 then
        WriteStr(11, 13, 'Unreadable sectors (zero-filled): ' + Num(BadSecs) + '   ', ATTR_NORMAL);
      MouseShow;

      if KeyWaiting then
      begin
        Ch := ReadKeyBIOS(Scan);
        if Ch = #27 then begin Aborted := True; Break; end;
      end;
    end;
    if Aborted or Failed then Break;
  end;
  BiosDiskReset(DriveNum);
  FloppyBufFree;

  if Aborted or Failed then
  begin
    KillOut;
    MouseHide;
    if Failed then
      WriteStr(11, 14, 'Cannot write output file (disk full?). Image removed.', ATTR_NORMAL)
    else
      WriteStr(11, 14, 'Aborted by user. Partial image removed.', ATTR_NORMAL);
    WaitKey;
    CloseDialog;
    Exit;
  end;
  Close(OutF);
  if IOResult <> 0 then ;
  FloppyReadDialog := True;
end;

procedure FloppyReadResult(const OutName: string; BadSecs: Word; const Msg: string; Opened: Boolean);
begin
  MouseHide;
  FillBox(8, 7, 71, 18, ' ', ATTR_DIALOG_BG);
  DrawFrame(8, 7, 71, 18, ATTR_DIALOG_BD, ' Read Complete ');
  WriteStr(11, 9, 'Image saved: ' + Copy(OutName, 1, 40), ATTR_DIALOG_HL);
  if BadSecs = 0 then
    WriteStr(11, 11, 'All ' + Num(SecDone) + ' sectors read successfully.', ATTR_DIALOG_BG)
  else
    WriteStr(11, 11, Num(BadSecs) + ' unreadable sector(s) were zero-filled!', ATTR_NORMAL);
  if Msg <> '' then WriteStr(11, 13, Msg, ATTR_DIALOG_BG);
  if Opened then WriteStr(11, 14, 'Image has been opened.', ATTR_DIALOG_BG);
  WaitKey;
  CloseDialog;
end;

end.
