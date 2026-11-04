{===========================================================================}
{   FILEDLG.PAS - Visual Host File Picker Dialog for STIMAGE DOS            }
{   Turbo Pascal 7.0 Real-Mode Compatible                                   }
{===========================================================================}
unit FileDlg;

{$R-,S-,I-,V-,A-}

interface

uses Dos, ScrKit, DiskTool;

const
  MAX_DIR_PICKER = 120;

  { Dialog Attributes }
  ATTR_NORMAL     = $1F;
  ATTR_DIR        = $1E;
  ATTR_BORDER     = $1B;
  ATTR_DIALOG_BG  = $70;
  ATTR_DIALOG_BD  = $7F;
  ATTR_DIALOG_HL  = $74;
  ATTR_DIALOG_INP = $1F;
  ATTR_DIALOG_SEL = $30;
  ATTR_MENU_SEL   = $30;

  { Scan codes }
  KEY_UP          = $48;
  KEY_DOWN        = $50;
  KEY_LEFT        = $4B;
  KEY_RIGHT       = $4D;
  KEY_PAGEUP      = $49;
  KEY_PAGEDOWN    = $51;
  KEY_HOME        = $47;
  KEY_END         = $4F;
  KEY_TAB         = $0F;
  KEY_F10         = $44;

type
  TPickerItem = record
    Name: string[12];
    IsDir: Boolean;
    Size: LongInt;
  end;

var
  PickerItems: array[1..MAX_DIR_PICKER] of TPickerItem;
  PickerCount: Integer;

procedure ScanHostDirectory(const Mask: string);
function  ShowFileDialog(var SelectedFile: string): Boolean;

implementation

procedure ScanHostDirectory(const Mask: string);
const
  Filters: array[1..4] of string[5] = ('*.ST', '*.MSA', '*.DIM', '*.ZIP');
var
  SR: SearchRec;
  I: Integer;
begin
  PickerCount := 0;

  Inc(PickerCount);
  PickerItems[PickerCount].Name := '..';
  PickerItems[PickerCount].IsDir := True;
  PickerItems[PickerCount].Size := 0;

  FindFirst('*.*', Directory, SR);
  while (DosError = 0) and (PickerCount < MAX_DIR_PICKER) do
  begin
    if ((SR.Attr and Directory) <> 0) and (SR.Name <> '.') and (SR.Name <> '..') then
    begin
      Inc(PickerCount);
      PickerItems[PickerCount].Name := SR.Name;
      PickerItems[PickerCount].IsDir := True;
      PickerItems[PickerCount].Size := 0;
    end;
    FindNext(SR);
  end;

  for I := 1 to 4 do
  begin
    FindFirst(Filters[I], Archive or ReadOnly, SR);
    while (DosError = 0) and (PickerCount < MAX_DIR_PICKER) do
    begin
      if (SR.Attr and Directory) = 0 then
      begin
        Inc(PickerCount);
        PickerItems[PickerCount].Name := SR.Name;
        PickerItems[PickerCount].IsDir := False;
        PickerItems[PickerCount].Size := SR.Size;
      end;
      FindNext(SR);
    end;
  end;
end;

function ShowFileDialog(var SelectedFile: string): Boolean;
var
  OkSelected: Boolean;
  CurDir: string[80];
  SelIdx, TopPIdx: Integer;
  Ch: Char;
  Scan: Byte;
  RowY, DIdx: Integer;
  Attr: Byte;
  LineStr: string;
  InputBuf: string[40];
  Saved: PPopupSave;
  ActiveBtn: Integer; { 0 = OK, 1 = Cancel }
  MX, MY: Integer;
  DblClick: Boolean;
  Event: Integer;

  procedure DoSelectOK;
  begin
    if InputBuf <> '' then
    begin
      SelectedFile := InputBuf;
      OkSelected := True;
    end
    else if (SelIdx >= 1) and (SelIdx <= PickerCount) then
    begin
      if PickerItems[SelIdx].IsDir then
      begin
        if ChangeHostDirTracked(PickerItems[SelIdx].Name) then
        begin
          GetDir(0, CurDir);
          ScanHostDirectory('*.ST');
          SelIdx := 1;
          TopPIdx := 1;
          ActiveBtn := 0;
        end;
      end
      else
      begin
        SelectedFile := PickerItems[SelIdx].Name;
        OkSelected := True;
      end;
    end;
  end;

begin
  OkSelected := False;
  GetDir(0, CurDir);
  ScanHostDirectory('*.ST');
  SelIdx := 1;
  TopPIdx := 1;
  InputBuf := '';
  ActiveBtn := 0;

  Saved := SaveArea(10, 2, 70, 22);

  repeat
    MouseHide;
    FillBox(10, 2, 70, 22, ' ', ATTR_DIALOG_BG);
    DrawFrame(10, 2, 70, 22, ATTR_DIALOG_BD, 'Open Atari ST Floppy Image');
    WriteStr(12, 3, 'Directory: ' + PadRight(CurDir, 45), ATTR_DIALOG_HL);

    { File list box }
    DrawFrame(12, 4, 68, 17, ATTR_BORDER, 'Files (*.ST; *.MSA; *.DIM; *.ZIP)');
    for RowY := 0 to 11 do
    begin
      DIdx := TopPIdx + RowY;
      if (DIdx >= 1) and (DIdx <= PickerCount) then
      begin
        if DIdx = SelIdx then
          Attr := ATTR_DIALOG_SEL
        else if PickerItems[DIdx].IsDir then
          Attr := ATTR_DIR
        else
          Attr := ATTR_DIALOG_BG;

        if PickerItems[DIdx].IsDir then
          LineStr := ' [' + PadRight(PickerItems[DIdx].Name + ']', 14) + '        <DIR>'
        else
          LineStr := '  ' + PadRight(PickerItems[DIdx].Name, 14) + ' ' +
                     PadLeft(FormatNum(PickerItems[DIdx].Size), 10) + ' B';

        WriteStr(13, 5 + RowY, PadRight(LineStr, 54), Attr);
      end
      else
        WriteStr(13, 5 + RowY, PadRight('', 54), ATTR_DIALOG_BG);
    end;

    { Input line }
    WriteStr(12, 18, 'File name: ', ATTR_DIALOG_BG);
    FillBox(23, 18, 68, 18, ' ', ATTR_DIALOG_INP);
    if InputBuf <> '' then
      WriteStr(23, 18, PadRight(InputBuf, 45), ATTR_DIALOG_INP)
    else if (SelIdx >= 1) and (SelIdx <= PickerCount) and (not PickerItems[SelIdx].IsDir) then
      WriteStr(23, 18, PadRight(PickerItems[SelIdx].Name, 45), ATTR_DIALOG_INP);

    { Buttons on Row 20 }
    if ActiveBtn = 0 then
    begin
      WriteStr(25, 20, '[  OK  ]', ATTR_MENU_SEL);
      WriteStr(40, 20, '[ Cancel ]', ATTR_DIALOG_HL);
    end
    else
    begin
      WriteStr(25, 20, '[  OK  ]', ATTR_DIALOG_HL);
      WriteStr(40, 20, '[ Cancel ]', ATTR_MENU_SEL);
    end;

    MouseShow;

    Event := GetInputEvent(Ch, Scan, MX, MY, DblClick);
    if Event = EVENT_KEY then
    begin
      if (Ch = #27) or (Scan = KEY_F10) then
      begin
        OkSelected := False;
        Break;
      end;

      if (Ch = #9) or (Scan = KEY_TAB) then
      begin
        ActiveBtn := 1 - ActiveBtn;
      end
      else if Scan = KEY_LEFT then
      begin
        ActiveBtn := 0; { OK }
      end
      else if Scan = KEY_RIGHT then
      begin
        ActiveBtn := 1; { Cancel }
      end
      else if Scan = KEY_UP then
      begin
        ActiveBtn := 0;
        if SelIdx > 1 then
        begin
          Dec(SelIdx);
          if SelIdx < TopPIdx then TopPIdx := SelIdx;
          InputBuf := '';
        end;
      end
      else if Scan = KEY_DOWN then
      begin
        ActiveBtn := 0;
        if SelIdx < PickerCount then
        begin
          Inc(SelIdx);
          if SelIdx >= TopPIdx + 12 then TopPIdx := SelIdx - 11;
          InputBuf := '';
        end;
      end
      else if Scan = KEY_PAGEUP then
      begin
        ActiveBtn := 0;
        SelIdx := SelIdx - 11;
        if SelIdx < 1 then SelIdx := 1;
        TopPIdx := TopPIdx - 11;
        if TopPIdx < 1 then TopPIdx := 1;
        InputBuf := '';
      end
      else if Scan = KEY_PAGEDOWN then
      begin
        ActiveBtn := 0;
        SelIdx := SelIdx + 11;
        if SelIdx > PickerCount then SelIdx := PickerCount;
        TopPIdx := TopPIdx + 11;
        if TopPIdx > PickerCount - 11 then TopPIdx := PickerCount - 11;
        if TopPIdx < 1 then TopPIdx := 1;
        InputBuf := '';
      end
      else if Scan = KEY_HOME then
      begin
        ActiveBtn := 0;
        SelIdx := 1;
        TopPIdx := 1;
        InputBuf := '';
      end
      else if Scan = KEY_END then
      begin
        ActiveBtn := 0;
        SelIdx := PickerCount;
        TopPIdx := PickerCount - 11;
        if TopPIdx < 1 then TopPIdx := 1;
        InputBuf := '';
      end
      else if Ch = #13 then { Enter }
      begin
        if ActiveBtn = 1 then
        begin
          OkSelected := False;
          Break;
        end
        else
        begin
          DoSelectOK;
          if OkSelected then Break;
        end;
      end
      else if (Ch = ' ') and (ActiveBtn = 1) then
      begin
        OkSelected := False;
        Break;
      end
      else if Ch = #8 then { Backspace }
      begin
        if InputBuf <> '' then
          Dec(InputBuf[0])
        else
        begin
          if ChangeHostDirTracked('..') then
          begin
            GetDir(0, CurDir);
            ScanHostDirectory('*.ST');
            SelIdx := 1;
            TopPIdx := 1;
            ActiveBtn := 0;
          end;
        end;
      end
      else if (Ch >= ' ') and (Ch <= '~') and (Length(InputBuf) < 40) then
      begin
        InputBuf := InputBuf + UpCase(Ch);
        ActiveBtn := 0;
      end;
    end
    else if Event = EVENT_CLICK then
    begin
      { Click outside dialog frame cancels }
      if (MX < 10) or (MX > 70) or (MY < 2) or (MY > 22) then
      begin
        OkSelected := False;
        Break;
      end
      { Click on [ OK ] button }
      else if (MY = 20) and (MX >= 24) and (MX <= 34) then
      begin
        ActiveBtn := 0;
        DoSelectOK;
        if OkSelected then Break;
      end
      { Click on [ Cancel ] button }
      else if (MY = 20) and (MX >= 38) and (MX <= 51) then
      begin
        ActiveBtn := 1;
        OkSelected := False;
        Break;
      end
      { Click on File List }
      else if (MY >= 5) and (MY <= 16) and (MX >= 12) and (MX <= 68) then
      begin
        DIdx := TopPIdx + (MY - 5);
        if (DIdx >= 1) and (DIdx <= PickerCount) then
        begin
          SelIdx := DIdx;
          InputBuf := '';
          ActiveBtn := 0;
          if DblClick then
          begin
            DoSelectOK;
            if OkSelected then Break;
          end;
        end;
      end
      { Click on File Name input box }
      else if (MY = 18) and (MX >= 12) and (MX <= 68) then
      begin
        ActiveBtn := 0;
      end;
    end;
  until False;

  MouseHide;
  RestoreArea(10, 2, 70, 22, Saved);
  MouseShow;
  ShowFileDialog := OkSelected;
end;

end.
