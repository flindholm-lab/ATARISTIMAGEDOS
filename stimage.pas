{===========================================================================}
{   STIMAGE for MS-DOS v2.1 - Atari ST Floppy Image Manager                 }
{   Built for Borland Turbo Pascal 7.0 (16-bit Real Mode x86)               }
{   Zero CRT Dependencies - Direct VRAM ($B800:0000) & BIOS Int 10h/16h/1Ah }
{   CGA / EGA / VGA 80x25 16-Color Text Mode                                }
{===========================================================================}
{$M 16384, 0, 393216}  { Stack: 16 KB, MinHeap: 0, MaxHeap: 384 KB for depacking large files }
{$R-,S-,I-,V-,A-}     { Fast execution, packed byte records, safe I/O checks }

program STImageDOS;

uses
  Dos, Depack, VirScan, DiskTool, ScrKit, FlopRead, FileDlg;

const
  APP_TITLE       = ' STIMAGE for MS-DOS v2.1 ';
  MAX_FILES       = 250;
  FAT_BUF_MAX     = 8192;   { Up to 16 sectors of FAT in memory }

  { CGA / EGA / VGA 16-Color Text Mode Attributes }
  ATTR_NORMAL     = $1F;  { White on Blue }
  ATTR_SELECTED   = $30;  { Black on Cyan (Cursor bar) }
  ATTR_DIR        = $1E;  { Yellow on Blue (Directories) }
  ATTR_DIR_SEL    = $3E;  { Yellow on Cyan }
  ATTR_DELETED    = $1C;  { Light Red on Blue (*d* deleted files) }
  ATTR_DEL_SEL    = $3C;  { Light Red on Cyan }
  ATTR_HIDDEN     = $1B;  { Light Cyan on Blue (*h* hidden files) }
  ATTR_HID_SEL    = $3B;  { Light Cyan on Cyan }
  ATTR_BORDER     = $1B;  { Light Cyan on Blue }
  ATTR_HEADER     = $1E;  { Yellow on Blue }
  ATTR_TITLE      = $70;  { Black on Light Gray }
  ATTR_STATUS     = $17;  { Light Gray on Blue }
  ATTR_KEY_NUM    = $30;  { Black on Cyan }
  ATTR_KEY_LBL    = $07;  { Light Gray on Black }
  ATTR_DIALOG_BG  = $70;  { Black on Light Gray }
  ATTR_DIALOG_BD  = $7F;  { White on Light Gray }
  ATTR_DIALOG_HL  = $74;  { Red on Light Gray }
  ATTR_DIALOG_OK  = $72;  { Green on Light Gray (Clean / OK status) }
  ATTR_DIALOG_ERR = $74;  { Red on Light Gray (Threat / Error status) }
  ATTR_DIALOG_INP = $1F;  { White on Blue (Input fields) }
  ATTR_DIALOG_SEL = $30;  { Black on Cyan (Picker bar) }
  ATTR_VIEW_HDR   = $1E;  { Yellow on Blue }
  ATTR_VIEW_TXT   = $07;  { Light Gray on Black }

  { Dropdown Menu Colors }
  ATTR_MENU_BAR   = $70;  { Black on Light Gray }
  ATTR_MENU_HOT   = $74;  { Red on Light Gray }
  ATTR_MENU_ACT   = $30;  { Black on Cyan }
  ATTR_MENU_BOX   = $70;  { Black on Light Gray }
  ATTR_MENU_BD    = $7F;  { White on Light Gray }
  ATTR_MENU_SEL   = $30;  { Black on Cyan }

  { BIOS Extended Key Codes (Int 16h AH register) }
  KEY_UP          = $48;
  KEY_DOWN        = $50;
  KEY_LEFT        = $4B;
  KEY_RIGHT       = $4D;
  KEY_PAGEUP      = $49;
  KEY_PAGEDOWN    = $51;
  KEY_HOME        = $47;
  KEY_END         = $4F;
  KEY_INSERT      = $52;
  KEY_DELETE      = $53;
  KEY_TAB         = $0F;
  KEY_F1          = $3B;
  KEY_F2          = $3C;
  KEY_F3          = $3D;
  KEY_F4          = $3E;
  KEY_F5          = $3F;
  KEY_F6          = $40;
  KEY_F7          = $41;
  KEY_F8          = $42;
  KEY_F9          = $43;
  KEY_F10         = $44;

  { Alt + Letter Keys }
  KEY_ALT_F       = $21;  { Alt+F (File Menu) }
  KEY_ALT_I       = $17;  { Alt+I (Image Menu) }
  KEY_ALT_V       = $2F;  { Alt+V (View Menu / VIEW.EXE) }
  KEY_ALT_H       = $23;  { Alt+H (Help Menu) }
  KEY_ALT_A       = $1E;  { Alt+A (Attributes) }
  KEY_ALT_R       = $13;  { Alt+R (Rename) }
  KEY_ALT_C       = $2E;  { Alt+C (Catalog) }
  KEY_ALT_X       = $2D;  { Alt+X (Exit) }

  { Top Menu Bar Constants }
  MENU_MAX        = 4;
  MenuNames: array[1..MENU_MAX] of string[8] = (' File ', ' Image ', ' View ', ' Help ');
  MenuHotkeys: array[1..MENU_MAX] of Char = ('F', 'I', 'V', 'H');
  MenuX: array[1..MENU_MAX] of Integer = (1, 9, 18, 26);

  { FAT12 Constants }
  FAT12_ENTRY_FREE    = $000;
  FAT12_ENTRY_BAD     = $FF7;
  FAT12_ENTRY_EOC_MIN = $FF8;
  FAT12_ENTRY_EOC     = $FFF;
  ATARI_BOOT_EXEC_SUM = $1234;

type
  TByteArray = array[0..32767] of Byte;
  PByteArray = ^TByteArray;
  TBigByteArray = array[0..65520] of Byte;
  PBigByteArray = ^TBigByteArray;
  PWordArr      = ^TWordArr;
  TWordArr      = array[0..4095] of Word;
  PByteArr      = ^TByteArr;
  TByteArr      = array[0..4095] of Byte;

  TString12 = string[12];
  TString80 = string[80];

  { Function Bar Definition }
  TBtnDef = record
    Num: string[2];
    Lbl: string[10];
    Width: Byte;
  end;

const
  BarButtons: array[1..10] of TBtnDef = (
    (Num: '1';  Lbl: 'Help';   Width: 6),
    (Num: '2';  Lbl: 'BPB';    Width: 6),
    (Num: '3';  Lbl: 'View';   Width: 6),
    (Num: '4';  Lbl: 'Hex';    Width: 6),
    (Num: '5';  Lbl: 'Extr';   Width: 7),
    (Num: '6';  Lbl: 'Add';    Width: 6),
    (Num: '7';  Lbl: 'MkDir';  Width: 7),
    (Num: '8';  Lbl: 'Del';    Width: 6),
    (Num: '9';  Lbl: 'New';    Width: 6),
    (Num: '10'; Lbl: 'Menu';   Width: 8)
  );

var
  { Program & Image State }
  Running: Boolean;
  AppDir: TString80;
  ActiveImagePath: TString80;
  ActiveImageFile: file;
  ImageIsOpen: Boolean;
  ImageIsReadOnly: Boolean;
  IsTempMSA: Boolean;
  OriginalMSAPath: TString80;
  IsTempZip: Boolean;
  OriginalZipPath: TString80;
  TempZipFile: TString80;
  IsTempDIM: Boolean;
  OriginalDIMPath: TString80;
  ActiveTempDir: TString80;

  BPB: TAtariBPB;
  Layout: TDiskLayout;
  RawBootSector: array[0..511] of Byte;
  FatBuf: array[0..FAT_BUF_MAX - 1] of Byte;

  { Directory browser state }
  Items: array[1..MAX_FILES] of TDiskItem;
  ItemCount: Integer;
  SelectedIdx: Integer;
  TopIdx: Integer;
  CurrentPath: TString80;
  CurrentDirCluster: Word;  { 0 = Root directory }

  { Active Viewer State }
  InViewer: Boolean;
  ViewerHexMode: Boolean;
  ViewerExitRequested: Boolean;
  CurrentViewHasDepacked: Boolean;
  CurrentViewIsDepacked: Boolean;
  ViewerDepackToggleRequested: Boolean;
  ViewerSaveDepackedRequested: Boolean;

{ Forward declarations }
procedure RenderScreen; forward;
procedure ShowClusterMapModal; forward;
procedure WriteImageToFloppyModal; forward;
procedure ReadFloppyToImageModal; forward;
procedure CloseImage; forward;
function OpenImage(const Path: string): Boolean; forward;
procedure ExtractActiveFile; forward;
procedure DeleteActiveFile; forward;
procedure UndeleteActiveFile; forward;
procedure CreateBlankDisk; forward;
procedure ViewFileText; forward;
procedure ViewFileHex; forward;
procedure InteractiveFileViewer(InitialHex: Boolean); forward;
procedure DepackActiveFile(ViewMode: Boolean); forward;
function ExtractSelectedFileTo(const DestPath: string): Boolean; forward;
function ExtractFileByClusterTo(StartClust: Word; FileSize: LongInt; const DestPath: string): Boolean; forward;
procedure ExtractAllAsZip; forward;
procedure ViewImageGraphic; forward;
procedure ShowBPBModal; forward;
procedure ShowBootSectorHexModal; forward;
procedure ShowVirusScannerModal; forward;
procedure MakeDiskPCCompatibleModal; forward;
procedure ShowSearchModal; forward;
procedure ShowCatalogModal; forward;
procedure ShowImportFileModal; forward;
procedure ShowRenameModal; forward;
procedure ShowAttrModal; forward;
procedure ShowMkdirModal; forward;
procedure DrawMenuBar(ActiveMenu: Integer); forward;
procedure ExecuteDropdownMenu(InitialMenu: Integer); forward;

{===========================================================================}
{   BIOS LOW-LEVEL & VIDEO ROUTINES (ZERO CRT)                              }
{===========================================================================}

{===========================================================================}
{   STRING & CONVERSION UTILITIES                                           }
{===========================================================================}

function IntToStr(V: LongInt): string;
var
  S: string;
begin
  Str(V, S);
  IntToStr := S;
end;

function Trim(const S: string): string;
var
  I, J: Integer;
begin
  I := 1;
  while (I <= Length(S)) and (S[I] = ' ') do Inc(I);
  J := Length(S);
  while (J >= I) and (S[J] = ' ') do Dec(J);
  if I > J then Trim := '' else Trim := Copy(S, I, J - I + 1);
end;

{===========================================================================}
{   ATARI ST / FAT12 PARSING & STREAMING ENGINE                             }
{===========================================================================}

procedure CloseImage;
var
  TempF: file;

  procedure EraseTempFile(const FName: string);
  begin
    if FName = '' then Exit;
    if IOResult <> 0 then ;
    Assign(TempF, FName);
    Erase(TempF);
    if IOResult <> 0 then ;
    if ActiveTempDir <> '' then
    begin
      Assign(TempF, ActiveTempDir + FName);
      Erase(TempF);
      if IOResult <> 0 then ;
    end;
    if AppDir <> '' then
    begin
      Assign(TempF, AppDir + FName);
      Erase(TempF);
      if IOResult <> 0 then ;
    end;
  end;

begin
  if ImageIsOpen then
  begin
    if IOResult <> 0 then ;
    Close(ActiveImageFile);
    if IOResult <> 0 then ;
    ImageIsOpen := False;
    if IsTempMSA then
    begin
      EraseTempFile('ST_MSA.$$$');
      IsTempMSA := False;
    end;
    if IsTempZip then
    begin
      EraseTempFile(TempZipFile);
      IsTempZip := False;
    end;
    if IsTempDIM then
    begin
      EraseTempFile('ST_DIM.$$$');
      IsTempDIM := False;
    end;
    EraseTempFile('ST_720.$$$');
    ActiveTempDir := '';
    ActiveImagePath := '';
    ItemCount := 0;
    SelectedIdx := 1;
    TopIdx := 1;
  end;
end;

function LoadBootAndBPB: Boolean;
begin
  LoadBootAndBPB := LoadDiskBootAndBPB(ActiveImageFile, BPB, Layout,
                      RawBootSector, @FatBuf, FAT_BUF_MAX);
end;

function FatGetEntry(Cluster: Word): Word;
var
  Off: Word;
  V: Word;
begin
  FatGetEntry := FAT12_ENTRY_EOC;
  if Cluster < 2 then Exit;
  Off := (Cluster * 3) div 2;
  if Off + 1 >= FAT_BUF_MAX then Exit;

  V := Word(FatBuf[Off]) or (Word(FatBuf[Off + 1]) shl 8);
  if (Cluster and 1) = 0 then
    FatGetEntry := V and $0FFF
  else
    FatGetEntry := V shr 4;
end;

procedure FatSetEntry(Cluster, Value: Word);
var
  Off: Word;
begin
  if Cluster < 2 then Exit;
  Off := (Cluster * 3) div 2;
  if Off + 1 >= FAT_BUF_MAX then Exit;

  if (Cluster and 1) = 0 then
  begin
    FatBuf[Off] := Value and $FF;
    FatBuf[Off + 1] := (FatBuf[Off + 1] and $F0) or ((Value shr 8) and $0F);
  end
  else
  begin
    FatBuf[Off] := (FatBuf[Off] and $0F) or ((Value shl 4) and $F0);
    FatBuf[Off + 1] := (Value shr 4) and $FF;
  end;
end;

procedure FlushFAT;
begin
  if ImageIsReadOnly then Exit;
  FlushDiskFAT(ActiveImageFile, Layout, BPB.NumberOfFATs, @FatBuf, FAT_BUF_MAX);
end;

function FindClusterOwner(TargetClust: Word; var OwnerName: TString12;
  var ChainIdx, ChainTotal: Integer; var IsCurrentSel: Boolean): Boolean;
var
  I: Integer;
  Clust: Word;
  Pos, Total: Integer;
  Found: Boolean;
begin
  FindClusterOwner := False;
  OwnerName := '';
  ChainIdx := 0;
  ChainTotal := 0;
  IsCurrentSel := False;
  if (TargetClust < 2) or (TargetClust > Layout.TotalClusters + 1) then Exit;

  for I := 1 to ItemCount do
  begin
    if (not Items[I].IsDir) and (Items[I].StartCluster >= 2) then
    begin
      Clust := Items[I].StartCluster;
      Pos := 0;
      Total := 0;
      Found := False;
      while (Clust >= 2) and (Clust < FAT12_ENTRY_EOC_MIN) do
      begin
        Inc(Total);
        if Clust = TargetClust then
        begin
          Found := True;
          Pos := Total;
        end;
        Clust := FatGetEntry(Clust);
      end;
      if Found then
      begin
        OwnerName := Items[I].CleanName;
        ChainIdx := Pos;
        ChainTotal := Total;
        IsCurrentSel := (I = SelectedIdx);
        FindClusterOwner := True;
        Exit;
      end;
    end;
  end;
end;

procedure CalculateFreeSpace;
begin
  CalcDiskFreeSpace(Layout, @FatBuf);
end;

procedure InspectPackersForItems;
var
  I: Integer;
  ClustOff: LongInt;
  HdrBuf: array[0..1023] of Byte;
  ActualRead: Word;
begin
  for I := 1 to ItemCount do
  begin
    if (not Items[I].IsDir) and (not Items[I].IsDeleted) and
       (Items[I].Size >= 4) and (Items[I].StartCluster >= 2) then
    begin
      ClustOff := Layout.DataAreaStart + (LongInt(Items[I].StartCluster - 2) * Layout.BytesPerCluster);
      Seek(ActiveImageFile, ClustOff);
      if IOResult = 0 then
      begin
        BlockRead(ActiveImageFile, HdrBuf, SizeOf(HdrBuf), ActualRead);
        if ActualRead >= 4 then
          Items[I].PackerTag := DetectPacker(@HdrBuf, ActualRead);
      end;
    end;
  end;
end;

procedure SortCurrentDirectory;
var
  I, J: Integer;
  Temp: TDiskItem;
  ShouldSwap: Boolean;
begin
  if ItemCount <= 1 then Exit;
  for I := 1 to ItemCount - 1 do
  begin
    for J := I + 1 to ItemCount do
    begin
      ShouldSwap := False;
      if Items[J].DisplayName = '..' then
        ShouldSwap := True
      else if Items[I].DisplayName = '..' then
        ShouldSwap := False
      else if Items[J].IsDir and (not Items[I].IsDir) then
        ShouldSwap := True
      else if (not Items[J].IsDir) and Items[I].IsDir then
        ShouldSwap := False
      else if Items[J].CleanName < Items[I].CleanName then
        ShouldSwap := True;

      if ShouldSwap then
      begin
        Temp := Items[I];
        Items[I] := Items[J];
        Items[J] := Temp;
      end;
    end;
  end;
end;

procedure ReadCurrentDirectory;
var
  SectorBuf: array[0..511] of Byte;
  EntryIdx: Integer;
  CurrentOff: LongInt;
  Item: TDiskItem;
  SecIdx: Word;
  Clust: Word;
  ActualRead: Word;
  DirFinished: Boolean;
begin
  ItemCount := 0;

  { Add parent directory [..] entry if we are inside a subdirectory }
  if CurrentDirCluster <> 0 then
  begin
    Inc(ItemCount);
    Items[ItemCount].DisplayName := '..';
    Items[ItemCount].CleanName := '..';
    Items[ItemCount].IsDir := True;
    Items[ItemCount].IsDeleted := False;
    Items[ItemCount].IsHidden := False;
    Items[ItemCount].Attr := $10;
    Items[ItemCount].Size := 0;
    Items[ItemCount].StartCluster := 0;
    Items[ItemCount].Year := 1985;
    Items[ItemCount].Month := 1;
    Items[ItemCount].Day := 1;
    Items[ItemCount].Hour := 0;
    Items[ItemCount].Min := 0;
    Items[ItemCount].PackerTag := '';
  end;

  DirFinished := False;

  if CurrentDirCluster = 0 then
  begin
    { Read Root Directory }
    CurrentOff := Layout.RootDirStart;
    for SecIdx := 0 to Layout.RootDirSectors - 1 do
    begin
      if DirFinished then Break;

      Seek(ActiveImageFile, CurrentOff);
      if IOResult <> 0 then Break;
      BlockRead(ActiveImageFile, SectorBuf, 512, ActualRead);
      if ActualRead < 512 then Break;

      for EntryIdx := 0 to 15 do
      begin
        if SectorBuf[EntryIdx * 32] = $00 then
        begin
          DirFinished := True;
          Break;
        end;

        if ParseDirEntry(@SectorBuf[EntryIdx * 32], CurrentOff + (EntryIdx * 32), Item) then
        begin
          if ItemCount < MAX_FILES then
          begin
            Inc(ItemCount);
            Items[ItemCount] := Item;
          end;
        end;
      end;
      if DirFinished then Break;
      CurrentOff := CurrentOff + 512;
    end;
  end
  else
  begin
    { Follow Subdirectory Cluster Chain }
    Clust := CurrentDirCluster;
    while (Clust >= 2) and (Clust < FAT12_ENTRY_EOC_MIN) and (not DirFinished) do
    begin
      CurrentOff := Layout.DataAreaStart + (LongInt(Clust - 2) * Layout.BytesPerCluster);
      for SecIdx := 0 to BPB.SectorsPerCluster - 1 do
      begin
        if DirFinished then Break;

        Seek(ActiveImageFile, CurrentOff);
        if IOResult <> 0 then Break;
        BlockRead(ActiveImageFile, SectorBuf, 512, ActualRead);
        if ActualRead < 512 then Break;

        for EntryIdx := 0 to 15 do
        begin
          if SectorBuf[EntryIdx * 32] = $00 then
          begin
            DirFinished := True;
            Break;
          end;

          if ParseDirEntry(@SectorBuf[EntryIdx * 32], CurrentOff + (EntryIdx * 32), Item) then
          begin
            if Item.IsDir and (Item.DisplayName = '..') then
            begin
              if (ItemCount >= 1) and (Items[1].DisplayName = '..') then
                Items[1].StartCluster := Item.StartCluster;
            end
            else
            begin
              if ItemCount < MAX_FILES then
              begin
                Inc(ItemCount);
                Items[ItemCount] := Item;
              end;
            end;
          end;
        end;
        if DirFinished then Break;
        CurrentOff := CurrentOff + 512;
      end;
      if (not DirFinished) and (Clust < FAT12_ENTRY_EOC_MIN) then
        Clust := FatGetEntry(Clust);
    end;
  end;

  if SelectedIdx > ItemCount then SelectedIdx := ItemCount;
  if SelectedIdx < 1 then SelectedIdx := 1;
  if TopIdx > ItemCount then TopIdx := 1;

  SortCurrentDirectory;
  InspectPackersForItems;
end;

type
  TZipCand = record
    Name: string[64];
    Method: Word;
    LocalOff: LongInt;
    UncompSize: LongInt;
  end;

function ExtractImageFromZip(const ZipPath: string; var ExtractedPath: string; var InnerMember: string): Boolean;
var
  ZipF, OutF, TempF: file;
  EOCD: TZipEOCD;
  CDH: TZipCDH;
  LFH: TZipLFH;
  FileSizeZip: LongInt;
  ScanPos, MaxSearch: LongInt;
  Sig: LongInt;
  EntryName: string[64];
  CandCount, SelCand: Integer;
  Candidates: array[1..16] of TZipCand;
  Ext3: string[4];
  I: Integer;
  Saved: PPopupSave;
  Ch: Char;
  Scan: Byte;
  ReadBytes: Word;
  UnzipCmdStr: string[128];
  UnzipProg: TString80;
  BaseName: string[16];
begin
  ExtractImageFromZip := False;
  ExtractedPath := '';
  InnerMember := '';
  CandCount := 0;
  if IOResult <> 0 then ;

  Assign(ZipF, ZipPath);
  Reset(ZipF, 1);
  if IOResult <> 0 then Exit;

  FileSizeZip := FileSize(ZipF);
  if FileSizeZip < 22 then
  begin
    Close(ZipF);
    Exit;
  end;

  MaxSearch := 1024;
  if MaxSearch > FileSizeZip - 22 then MaxSearch := FileSizeZip - 22;
  ScanPos := FileSizeZip - 22;
  Sig := 0;
  while (ScanPos >= FileSizeZip - 22 - MaxSearch) and (ScanPos >= 0) do
  begin
    Seek(ZipF, ScanPos);
    if IOResult <> 0 then Break;
    BlockRead(ZipF, Sig, 4, ReadBytes);
    if Sig = $06054B50 then Break;
    Dec(ScanPos);
  end;

  if Sig <> $06054B50 then
  begin
    Close(ZipF);
    Exit;
  end;

  Seek(ZipF, ScanPos);
  BlockRead(ZipF, EOCD, SizeOf(EOCD), ReadBytes);
  if ReadBytes < SizeOf(EOCD) then
  begin
    Close(ZipF);
    Exit;
  end;

  Seek(ZipF, EOCD.CDOffset);
  if IOResult <> 0 then
  begin
    Close(ZipF);
    Exit;
  end;

  for I := 1 to EOCD.TotalEntries do
  begin
    BlockRead(ZipF, CDH, SizeOf(CDH), ReadBytes);
    if (ReadBytes < SizeOf(CDH)) or (CDH.Sig <> $02014B50) then Break;

    EntryName := '';
    if CDH.NameLen > 64 then
    begin
      BlockRead(ZipF, EntryName[1], 64, ReadBytes);
      EntryName[0] := Chr(64);
      Seek(ZipF, FilePos(ZipF) + (CDH.NameLen - 64));
    end
    else
    begin
      BlockRead(ZipF, EntryName[1], CDH.NameLen, ReadBytes);
      EntryName[0] := Chr(CDH.NameLen);
    end;

    if (CDH.ExtraLen + CDH.CommentLen) > 0 then
      Seek(ZipF, FilePos(ZipF) + CDH.ExtraLen + CDH.CommentLen);

    if Length(EntryName) >= 4 then
    begin
      Ext3 := Copy(EntryName, Length(EntryName) - 3, 4);
      for Scan := 1 to Length(Ext3) do Ext3[Scan] := UpCase(Ext3[Scan]);
      if (Ext3 = '.ST ') or (Ext3 = '.ST') or (Ext3 = '.MSA') or
         (Ext3 = '.DIM') or (Ext3 = '.IMG') then
      begin
        if CandCount < 8 then
        begin
          Inc(CandCount);
          Candidates[CandCount].Name := EntryName;
          Candidates[CandCount].Method := CDH.Method;
          Candidates[CandCount].LocalOff := CDH.LocalHdrOffset;
          Candidates[CandCount].UncompSize := CDH.UncompSize;
        end;
      end;
    end;
  end;
  Close(ZipF);

  if CandCount = 0 then
  begin
    Saved := SaveArea(15, 10, 65, 14);
    FillBox(15, 10, 65, 14, ' ', ATTR_DIALOG_BG);
    DrawFrame(15, 10, 65, 14, ATTR_DIALOG_BD, 'Open Image in ZIP');
    WriteStr(17, 12, 'No floppy image (.ST/.MSA/.DIM) found! [Key]', ATTR_DIALOG_HL);
    ReadKeyBIOS(Scan);
    RestoreArea(15, 10, 65, 14, Saved);
    Exit;
  end;

  SelCand := 1;
  if CandCount > 1 then
  begin
    Saved := SaveArea(12, 6, 68, 18);
    repeat
      FillBox(12, 6, 68, 18, ' ', ATTR_DIALOG_BG);
      DrawFrame(12, 6, 68, 18, ATTR_DIALOG_BD, 'Select Disk Image Inside ZIP');
      for I := 1 to CandCount do
      begin
        if I = SelCand then
          WriteStr(15, 7 + I, PadRight('> ' + Copy(Candidates[I].Name, 1, 35) + ' (' +
            IntToStr(Candidates[I].UncompSize div 1024) + ' KB)', 50), ATTR_DIALOG_SEL)
        else
          WriteStr(15, 7 + I, PadRight('  ' + Copy(Candidates[I].Name, 1, 35) + ' (' +
            IntToStr(Candidates[I].UncompSize div 1024) + ' KB)', 50), ATTR_DIALOG_BG);
      end;
      WriteStr(15, 16, '[Enter] Select   [Esc] Cancel', ATTR_DIALOG_HL);
      Ch := ReadKeyBIOS(Scan);
      if Ch = #0 then
      begin
        if (Scan = KEY_UP) and (SelCand > 1) then Dec(SelCand);
        if (Scan = KEY_DOWN) and (SelCand < CandCount) then Inc(SelCand);
      end
      else if Ch = #27 then
      begin
        RestoreArea(12, 6, 68, 18, Saved);
        Exit;
      end;
    until Ch = #13;
    RestoreArea(12, 6, 68, 18, Saved);
  end;

  InnerMember := Candidates[SelCand].Name;

  Saved := SaveArea(15, 10, 65, 14);
  FillBox(15, 10, 65, 14, ' ', ATTR_DIALOG_BG);
  DrawFrame(15, 10, 65, 14, ATTR_DIALOG_BD, 'ZIP Archive Extractor');
  WriteStr(17, 12, 'Extracting ' + Copy(InnerMember, 1, 24) + '...', ATTR_DIALOG_HL);

  if Candidates[SelCand].Method = 0 then
  begin
    if not ExtractStoredZipMember(ZipPath, Candidates[SelCand].LocalOff,
                                  Candidates[SelCand].UncompSize, 'ST_ZIP.$$$') then
    begin
      RestoreArea(15, 10, 65, 14, Saved);
      Exit;
    end;
    ExtractedPath := 'ST_ZIP.$$$';
  end
  else
  begin
    UnzipCmdStr := '-o -j ' + ZipPath + ' ' + InnerMember + ' -d .';
    if ResolveHelperExe('UNZIP.EXE', AppDir, UnzipProg) then
      SafeExec(UnzipProg, UnzipCmdStr)
    else
      SafeExec('UNZIP.EXE', UnzipCmdStr);

    BaseName := InnerMember;
    for I := Length(BaseName) downto 1 do
      if (BaseName[I] = '/') or (BaseName[I] = '\') then
      begin
        BaseName := Copy(BaseName, I + 1, Length(BaseName) - I);
        Break;
      end;
    for I := 1 to Length(BaseName) do BaseName[I] := UpCase(BaseName[I]);

    if IOResult <> 0 then ;
    Assign(OutF, BaseName);
    Reset(OutF, 1);
    if IOResult = 0 then
    begin
      Close(OutF);
      Assign(OutF, BaseName);
      Assign(TempF, 'ST_ZIP.$$$');
      Erase(TempF);
      if IOResult <> 0 then ;
      Rename(OutF, 'ST_ZIP.$$$');
      if IOResult <> 0 then ;
      ExtractedPath := 'ST_ZIP.$$$';
    end
    else
    begin
      RestoreArea(15, 10, 65, 14, Saved);
      Exit;
    end;
  end;

  RestoreArea(15, 10, 65, 14, Saved);
  ExtractImageFromZip := True;
end;

function OpenImage(const Path: string): Boolean;
var
  Ext: string[4];
  IsMSA, IsZip, IsDIM: Boolean;
  CheckF: file;
  Magic: array[0..1] of Byte;
  ActualRead: Word;
  Saved: PPopupSave;
  Scan: Byte;
  I: Integer;
  ExtractedZipPath, InnerMember: string;
begin
  OpenImage := False;
  CloseImage;

  if IOResult <> 0 then ;
  GetDir(0, ActiveTempDir);
  if IOResult <> 0 then ActiveTempDir := '';
  if (ActiveTempDir <> '') and (ActiveTempDir[Length(ActiveTempDir)] <> '\') then
    ActiveTempDir := ActiveTempDir + '\';

  IsZip := False;
  IsMSA := False;
  IsDIM := False;
  if Length(Path) >= 4 then
  begin
    Ext := Copy(Path, Length(Path) - 3, 4);
    for I := 1 to Length(Ext) do Ext[I] := UpCase(Ext[I]);
    if Ext = '.ZIP' then IsZip := True
    else if Ext = '.MSA' then IsMSA := True
    else if Ext = '.DIM' then IsDIM := True;
  end;

  if (not IsZip) and (not IsMSA) and (not IsDIM) then
  begin
    Assign(CheckF, Path);
    Reset(CheckF, 1);
    if IOResult = 0 then
    begin
      BlockRead(CheckF, Magic, 2, ActualRead);
      Close(CheckF);
      if (ActualRead = 2) then
      begin
        if (Magic[0] = $0E) and (Magic[1] = $0F) then
          IsMSA := True
        else if (Magic[0] = $42) and (Magic[1] = $42) then
          IsDIM := True
        else if (Magic[0] = $50) and (Magic[1] = $4B) then
          IsZip := True;
      end;
    end;
  end;

  if IsZip then
  begin
    if not ExtractImageFromZip(Path, ExtractedZipPath, InnerMember) then Exit;

    IsMSA := False;
    IsDIM := False;
    if Length(InnerMember) >= 4 then
    begin
      Ext := Copy(InnerMember, Length(InnerMember) - 3, 4);
      for I := 1 to Length(Ext) do Ext[I] := UpCase(Ext[I]);
      if Ext = '.MSA' then IsMSA := True
      else if Ext = '.DIM' then IsDIM := True;
    end;

    if (not IsMSA) and (not IsDIM) then
    begin
      if IOResult <> 0 then ;
      Assign(CheckF, ExtractedZipPath);
      Reset(CheckF, 1);
      if IOResult = 0 then
      begin
        BlockRead(CheckF, Magic, 2, ActualRead);
        Close(CheckF);
        if ActualRead = 2 then
        begin
          if (Magic[0] = $0E) and (Magic[1] = $0F) then
            IsMSA := True
          else if (Magic[0] = $42) and (Magic[1] = $42) then
            IsDIM := True;
        end;
      end;
    end;

    if IsMSA then
    begin
      Saved := SaveArea(15, 10, 65, 14);
      FillBox(15, 10, 65, 14, ' ', ATTR_DIALOG_BG);
      DrawFrame(15, 10, 65, 14, ATTR_DIALOG_BD, 'Magic Shadow Archiver');
      WriteStr(17, 12, 'Decompressing .MSA Disk Image...', ATTR_DIALOG_HL);

      if not UnpackMSAToFile(ExtractedZipPath, 'ST_MSA.$$$') then
      begin
        WriteStr(17, 12, 'Error decompressing MSA archive! [Key] ', ATTR_DIALOG_HL);
        ReadKeyBIOS(Scan);
        RestoreArea(15, 10, 65, 14, Saved);
        Assign(CheckF, ExtractedZipPath); Erase(CheckF);
        if IOResult <> 0 then ;
        Exit;
      end;
      RestoreArea(15, 10, 65, 14, Saved);
      Assign(CheckF, ExtractedZipPath); Erase(CheckF);
      if IOResult <> 0 then ;

      Assign(ActiveImageFile, 'ST_MSA.$$$');
      Reset(ActiveImageFile, 1);
      if IOResult <> 0 then Exit;

      ImageIsOpen := True;
      IsTempMSA := True;
      IsTempZip := True;
      TempZipFile := 'ST_MSA.$$$';
      OriginalZipPath := Path;
      ActiveImagePath := Path;
      ImageIsReadOnly := True;
    end
    else if IsDIM then
    begin
      Saved := SaveArea(15, 10, 65, 14);
      FillBox(15, 10, 65, 14, ' ', ATTR_DIALOG_BG);
      DrawFrame(15, 10, 65, 14, ATTR_DIALOG_BD, 'FastCopy Pro DIM');
      WriteStr(17, 12, 'Unpacking .DIM Disk Image...', ATTR_DIALOG_HL);

      if not UnpackDIMToFile(ExtractedZipPath, 'ST_DIM.$$$') then
      begin
        WriteStr(17, 12, 'Error unpacking DIM image! [Key]   ', ATTR_DIALOG_HL);
        ReadKeyBIOS(Scan);
        RestoreArea(15, 10, 65, 14, Saved);
        Assign(CheckF, ExtractedZipPath); Erase(CheckF);
        if IOResult <> 0 then ;
        Exit;
      end;
      RestoreArea(15, 10, 65, 14, Saved);
      Assign(CheckF, ExtractedZipPath); Erase(CheckF);
      if IOResult <> 0 then ;

      Assign(ActiveImageFile, 'ST_DIM.$$$');
      Reset(ActiveImageFile, 1);
      if IOResult <> 0 then Exit;

      ImageIsOpen := True;
      IsTempMSA := False;
      IsTempDIM := True;
      IsTempZip := True;
      TempZipFile := 'ST_DIM.$$$';
      OriginalZipPath := Path;
      ActiveImagePath := Path;
      ImageIsReadOnly := True;
    end
    else
    begin
      Assign(ActiveImageFile, ExtractedZipPath);
      Reset(ActiveImageFile, 1);
      if IOResult <> 0 then Exit;

      ImageIsOpen := True;
      IsTempMSA := False;
      IsTempZip := True;
      TempZipFile := ExtractedZipPath;
      OriginalZipPath := Path;
      ActiveImagePath := Path;
      ImageIsReadOnly := True;
    end;
  end
  else if IsMSA then
  begin
    Saved := SaveArea(15, 10, 65, 14);
    FillBox(15, 10, 65, 14, ' ', ATTR_DIALOG_BG);
    DrawFrame(15, 10, 65, 14, ATTR_DIALOG_BD, 'Magic Shadow Archiver');
    WriteStr(17, 12, 'Decompressing .MSA Disk Image...', ATTR_DIALOG_HL);

    if not UnpackMSAToFile(Path, 'ST_MSA.$$$') then
    begin
      WriteStr(17, 12, 'Error decompressing MSA archive! [Key] ', ATTR_DIALOG_HL);
      ReadKeyBIOS(Scan);
      RestoreArea(15, 10, 65, 14, Saved);
      Exit;
    end;
    RestoreArea(15, 10, 65, 14, Saved);

    Assign(ActiveImageFile, 'ST_MSA.$$$');
    Reset(ActiveImageFile, 1);
    if IOResult <> 0 then Exit;

    ImageIsOpen := True;
    IsTempMSA := True;
    IsTempZip := False;
    OriginalMSAPath := Path;
    ActiveImagePath := Path;
    ImageIsReadOnly := True;
  end
  else if IsDIM then
  begin
    Saved := SaveArea(15, 10, 65, 14);
    FillBox(15, 10, 65, 14, ' ', ATTR_DIALOG_BG);
    DrawFrame(15, 10, 65, 14, ATTR_DIALOG_BD, 'FastCopy Pro DIM');
    WriteStr(17, 12, 'Unpacking .DIM Disk Image...', ATTR_DIALOG_HL);

    if not UnpackDIMToFile(Path, 'ST_DIM.$$$') then
    begin
      WriteStr(17, 12, 'Error unpacking DIM image! [Key]   ', ATTR_DIALOG_HL);
      ReadKeyBIOS(Scan);
      RestoreArea(15, 10, 65, 14, Saved);
      Exit;
    end;
    RestoreArea(15, 10, 65, 14, Saved);

    Assign(ActiveImageFile, 'ST_DIM.$$$');
    Reset(ActiveImageFile, 1);
    if IOResult <> 0 then Exit;

    ImageIsOpen := True;
    IsTempMSA := False;
    IsTempZip := False;
    IsTempDIM := True;
    OriginalDIMPath := Path;
    ActiveImagePath := Path;
    ImageIsReadOnly := True;
  end
  else
  begin
    Assign(ActiveImageFile, Path);
    Reset(ActiveImageFile, 1);
    if IOResult <> 0 then Exit;

    ImageIsOpen := True;
    IsTempMSA := False;
    IsTempZip := False;
    OriginalMSAPath := '';
    ActiveImagePath := Path;
    ImageIsReadOnly := False;
  end;

  if not LoadBootAndBPB then
  begin
    CloseImage;
    Exit;
  end;

  CalculateFreeSpace;
  CurrentPath := '\';
  CurrentDirCluster := 0;
  SelectedIdx := 1;
  TopIdx := 1;
  ReadCurrentDirectory;

  OpenImage := True;
end;

{===========================================================================}
{   FILE OPERATIONS (EXTRACT, INSERT, DELETE, UNDELETE, MKDIR, NEW DISK)    }
{===========================================================================}

function ExtractFileByClusterTo(StartClust: Word; FileSize: LongInt; const DestPath: string): Boolean;
begin
  ExtractFileByClusterTo := ExtractClusterChainToFile(ActiveImageFile, Layout.DataAreaStart,
    Layout.BytesPerCluster, @FatBuf, StartClust, FileSize, DestPath);
end;

function ExtractSelectedFileTo(const DestPath: string): Boolean;
begin
  ExtractSelectedFileTo := False;
  if (ItemCount = 0) or (SelectedIdx < 1) or (SelectedIdx > ItemCount) then Exit;
  if Items[SelectedIdx].IsDir then Exit;
  ExtractSelectedFileTo := ExtractFileByClusterTo(Items[SelectedIdx].StartCluster,
                                                  Items[SelectedIdx].Size,
                                                  DestPath);
end;

procedure ExtractActiveFile;
var
  TargetName: TString80;
  InputName: string[12];
  Scan: Byte;
  Ch: Char;
  Saved: PPopupSave;
  ActiveBtn: Integer;
  MX, MY: Integer;
  DblClick: Boolean;
  Event: Integer;
begin
  if (ItemCount = 0) or (SelectedIdx < 1) or (SelectedIdx > ItemCount) then Exit;
  if Items[SelectedIdx].IsDir then Exit;

  InputName := Items[SelectedIdx].CleanName;
  Saved := SaveArea(12, 8, 68, 16);
  FillBox(12, 8, 68, 16, ' ', ATTR_DIALOG_BG);
  DrawFrame(12, 8, 68, 16, ATTR_DIALOG_BD, 'Extract File to DOS');
  WriteStr(15, 10, 'File on Image:  ' + Items[SelectedIdx].CleanName, ATTR_DIALOG_BG);
  WriteStr(15, 11, 'File Size:      ' + FormatNum(Items[SelectedIdx].Size) + ' bytes', ATTR_DIALOG_BG);
  WriteStr(15, 12, 'Destination:    ' + InputName, ATTR_DIALOG_HL);

  ActiveBtn := 0;
  repeat
    MouseHide;
    if ActiveBtn = 0 then
    begin
      WriteStr(18, 14, '[  Extract (Enter)  ]', ATTR_MENU_SEL);
      WriteStr(42, 14, '[  Cancel (Esc)  ]', ATTR_DIALOG_HL);
    end
    else
    begin
      WriteStr(18, 14, '[  Extract (Enter)  ]', ATTR_DIALOG_HL);
      WriteStr(42, 14, '[  Cancel (Esc)  ]', ATTR_MENU_SEL);
    end;
    MouseShow;

    Event := GetInputEvent(Ch, Scan, MX, MY, DblClick);
    if Event = EVENT_KEY then
    begin
      if (Ch = #27) or (Scan = KEY_F10) then
      begin
        MouseHide;
        RestoreArea(12, 8, 68, 16, Saved);
        MouseShow;
        Exit;
      end;
      if (Ch = #9) or (Scan = KEY_TAB) or (Scan = KEY_LEFT) or (Scan = KEY_RIGHT) then
        ActiveBtn := 1 - ActiveBtn
      else if (Ch = #13) or (Ch = ' ') then
      begin
        if ActiveBtn = 1 then
        begin
          MouseHide;
          RestoreArea(12, 8, 68, 16, Saved);
          MouseShow;
          Exit;
        end
        else Break;
      end;
    end
    else if Event = EVENT_CLICK then
    begin
      if (MY = 14) and (MX >= 18) and (MX <= 38) then
      begin
        ActiveBtn := 0;
        Break;
      end
      else if (MY = 14) and (MX >= 42) and (MX <= 59) then
      begin
        MouseHide;
        RestoreArea(12, 8, 68, 16, Saved);
        MouseShow;
        Exit;
      end
      else if (MX < 12) or (MX > 68) or (MY < 8) or (MY > 16) then
      begin
        MouseHide;
        RestoreArea(12, 8, 68, 16, Saved);
        MouseShow;
        Exit;
      end;
    end;
  until False;

  MouseHide;
  TargetName := InputName;
  WriteStr(15, 14, PadRight('Extracting ' + TargetName + '...', 50), ATTR_DIALOG_HL);

  if ExtractSelectedFileTo(TargetName) then
    WriteStr(15, 14, 'Extracted ' + FormatNum(Items[SelectedIdx].Size) + ' B! Press any key.', ATTR_DIALOG_HL)
  else
    WriteStr(15, 14, 'Error extracting file to DOS! Press any key.', ATTR_DIALOG_HL);

  MouseShow;
  GetInputEvent(Ch, Scan, MX, MY, DblClick);
  MouseHide;
  RestoreArea(12, 8, 68, 16, Saved);
  MouseShow;
end;

procedure ExtractAllAsZip;
var
  TargetZip: TString80;
  DefaultZip: string[12];
  DepackOpt: Char;
  Saved: PPopupSave;
  Ch: Char;
  Scan: Byte;
  I: Integer;
  BaseName: string[12];
  ActiveBtn: Integer;
  MX, MY: Integer;
  DblClick: Boolean;
  Event: Integer;
begin
  if (not ImageIsOpen) or (ActiveImagePath = '') then Exit;


  BaseName := '';
  for I := Length(ActiveImagePath) downto 1 do
    if (ActiveImagePath[I] = '\') or (ActiveImagePath[I] = '/') or (ActiveImagePath[I] = ':') then
    begin
      BaseName := Copy(ActiveImagePath, I + 1, Length(ActiveImagePath) - I);
      Break;
    end;
  if BaseName = '' then BaseName := ActiveImagePath;
  for I := 1 to Length(BaseName) do
    if BaseName[I] = '.' then
    begin
      BaseName := Copy(BaseName, 1, I - 1);
      Break;
    end;
  if Length(BaseName) > 8 then BaseName := Copy(BaseName, 1, 8);
  DefaultZip := BaseName + '.ZIP';

  Saved := SaveArea(12, 6, 68, 17);
  FillBox(12, 6, 68, 17, ' ', ATTR_DIALOG_BG);
  DrawFrame(12, 6, 68, 17, ATTR_DIALOG_BD, 'Extract All Files as ZIP Archive');

  WriteStr(14, 8, 'Target ZIP file: ', ATTR_DIALOG_BG);
  FillBox(31, 8, 64, 8, ' ', ATTR_DIALOG_INP);
  TargetZip := DefaultZip;
  WriteStr(31, 8, PadRight(TargetZip, 34), ATTR_DIALOG_INP);

  WriteStr(14, 10, 'Depack packed files? (Y/N): [Y]', ATTR_DIALOG_HL);
  WriteStr(14, 12, 'Includes all root & subfolder files.', ATTR_DIALOG_BG);
  WriteStr(14, 13, 'Creates standard PKZIP 2.0 archive.', ATTR_DIALOG_BG);
  WriteStr(22, 15, '[  OK  ]       [ Cancel ]', ATTR_DIALOG_HL);

  PromptInput(31, 8, TargetZip, 30);
  if TargetZip = '' then TargetZip := DefaultZip;

  WriteStr(43, 10, ' ', ATTR_DIALOG_INP);
  SetCursorPos(43, 10);
  ShowCursor;
  repeat
    Ch := ReadKeyBIOS(Scan);
    if Ch = #13 then Ch := 'Y';
    if Ch = #27 then
    begin
      HideCursor;
      RestoreArea(12, 6, 68, 17, Saved);
      Exit;
    end;
    Ch := UpCase(Ch);
  until (Ch = 'Y') or (Ch = 'N');
  DepackOpt := Ch;
  WriteStr(43, 10, DepackOpt, ATTR_DIALOG_INP);
  HideCursor;

  ActiveBtn := 0;
  repeat
    MouseHide;
    if ActiveBtn = 0 then
    begin
      WriteStr(22, 15, '[  OK  ]', ATTR_MENU_SEL);
      WriteStr(37, 15, '[ Cancel ]', ATTR_DIALOG_HL);
    end
    else
    begin
      WriteStr(22, 15, '[  OK  ]', ATTR_DIALOG_HL);
      WriteStr(37, 15, '[ Cancel ]', ATTR_MENU_SEL);
    end;
    MouseShow;
    Event := GetInputEvent(Ch, Scan, MX, MY, DblClick);
    if Event = EVENT_KEY then
    begin
      if (Ch = #27) or (Scan = KEY_F10) then
      begin
        MouseHide;
        RestoreArea(12, 6, 68, 17, Saved);
        MouseShow;
        Exit;
      end;
      if (Ch = #9) or (Scan = KEY_TAB) or (Scan = KEY_LEFT) or (Scan = KEY_RIGHT) then
        ActiveBtn := 1 - ActiveBtn
      else if (Ch = #13) or (Ch = ' ') then
      begin
        if ActiveBtn = 1 then
        begin
          MouseHide;
          RestoreArea(12, 6, 68, 17, Saved);
          MouseShow;
          Exit;
        end
        else Break;
      end;
    end
    else if Event = EVENT_CLICK then
    begin
      if (MY = 15) and (MX >= 22) and (MX <= 30) then
      begin
        ActiveBtn := 0;
        Break;
      end
      else if (MY = 15) and (MX >= 37) and (MX <= 48) then
      begin
        MouseHide;
        RestoreArea(12, 6, 68, 17, Saved);
        MouseShow;
        Exit;
      end
      else if (MX < 12) or (MX > 68) or (MY < 6) or (MY > 17) then
      begin
        MouseHide;
        RestoreArea(12, 6, 68, 17, Saved);
        MouseShow;
        Exit;
      end;
    end;
  until False;
  MouseHide;

  if (Length(TargetZip) < 4) or
     ((Copy(TargetZip, Length(TargetZip) - 3, 4) <> '.ZIP') and
      (Copy(TargetZip, Length(TargetZip) - 3, 4) <> '.zip')) then
    TargetZip := TargetZip + '.ZIP';

  WriteStr(14, 15, 'Creating ZIP archive... Please wait.', ATTR_DIALOG_HL);
  if ExportDiskAsZip(ActiveImageFile, Layout.DataAreaStart, Layout.BytesPerCluster,
                     Layout.RootDirStart, Layout.RootDirSectors, BPB.SectorsPerCluster,
                     @FatBuf, TargetZip, DepackOpt = 'Y') then
    WriteStr(14, 15, 'ZIP archive created successfully!   ', ATTR_DIALOG_HL)
  else
    WriteStr(14, 15, 'Error writing ZIP archive!           ', ATTR_STATUS);

  WriteStr(22, 16, 'Press any key...', ATTR_DIALOG_BG);
  ReadKeyBIOS(Scan);
  RestoreArea(12, 6, 68, 17, Saved);
end;

procedure DeleteActiveFile;
var
  Ch: Char;
  Scan: Byte;
  Clust, NextClust: Word;
  DelMarker: Byte;
  Saved: PPopupSave;
  ActiveBtn: Integer;
  MX, MY: Integer;
  DblClick: Boolean;
  Event: Integer;
begin
  if (ItemCount = 0) or (SelectedIdx < 1) or (SelectedIdx > ItemCount) then Exit;
  if Items[SelectedIdx].DisplayName = '..' then Exit;
  if Items[SelectedIdx].IsDeleted then Exit;

  if ImageIsReadOnly then
  begin
    Saved := SaveArea(14, 9, 66, 15);
    MouseHide;
    FillBox(14, 9, 66, 15, ' ', ATTR_DIALOG_BG);
    DrawFrame(14, 9, 66, 15, ATTR_DIALOG_BD, 'Delete Item');
    WriteStr(17, 11, 'Cannot delete: Image is read-only!', ATTR_DIALOG_HL);
    WriteStr(17, 13, 'Press any key to return...', ATTR_STATUS);
    MouseShow;
    ReadKeyBIOS(Scan);
    RestoreArea(14, 9, 66, 15, Saved);
    Exit;
  end;

  Saved := SaveArea(15, 8, 65, 14);
  FillBox(15, 8, 65, 14, ' ', ATTR_DIALOG_BG);
  DrawFrame(15, 8, 65, 14, ATTR_DIALOG_BD, 'Confirm File Deletion');
  WriteStr(17, 10, 'Delete: ' + Items[SelectedIdx].DisplayName + ' ?', ATTR_DIALOG_BG);

  ActiveBtn := 1;
  repeat
    MouseHide;
    if ActiveBtn = 0 then
    begin
      WriteStr(20, 12, '[  Delete (Y)  ]', ATTR_MENU_SEL);
      WriteStr(38, 12, '[ Cancel (Esc) ]', ATTR_DIALOG_HL);
    end
    else
    begin
      WriteStr(20, 12, '[  Delete (Y)  ]', ATTR_DIALOG_HL);
      WriteStr(38, 12, '[ Cancel (Esc) ]', ATTR_MENU_SEL);
    end;
    MouseShow;

    Event := GetInputEvent(Ch, Scan, MX, MY, DblClick);
    if Event = EVENT_KEY then
    begin
      if (Ch = #27) or (UpCase(Ch) = 'N') or (Scan = KEY_F10) then
      begin
        MouseHide;
        RestoreArea(15, 8, 65, 14, Saved);
        MouseShow;
        Exit;
      end;
      if (Ch = #9) or (Scan = KEY_TAB) or (Scan = KEY_LEFT) or (Scan = KEY_RIGHT) then
        ActiveBtn := 1 - ActiveBtn
      else if UpCase(Ch) = 'Y' then
      begin
        ActiveBtn := 0;
        Break;
      end
      else if (Ch = #13) or (Ch = ' ') then
      begin
        if ActiveBtn = 1 then
        begin
          MouseHide;
          RestoreArea(15, 8, 65, 14, Saved);
          MouseShow;
          Exit;
        end
        else Break;
      end;
    end
    else if Event = EVENT_CLICK then
    begin
      if (MY = 12) and (MX >= 20) and (MX <= 35) then
      begin
        ActiveBtn := 0;
        Break;
      end
      else if (MY = 12) and (MX >= 38) and (MX <= 54) then
      begin
        MouseHide;
        RestoreArea(15, 8, 65, 14, Saved);
        MouseShow;
        Exit;
      end
      else if (MX < 15) or (MX > 65) or (MY < 8) or (MY > 14) then
      begin
        MouseHide;
        RestoreArea(15, 8, 65, 14, Saved);
        MouseShow;
        Exit;
      end;
    end;
  until False;
  MouseHide;
  RestoreArea(15, 8, 65, 14, Saved);
  MouseShow;

  { 1. Mark directory entry first byte as $E5 }
  DelMarker := $E5;
  Seek(ActiveImageFile, Items[SelectedIdx].EntryOffset);
  if IOResult = 0 then
    BlockWrite(ActiveImageFile, DelMarker, 1);

  { 2. Free cluster chain in FAT }
  Clust := Items[SelectedIdx].StartCluster;
  while (Clust >= 2) and (Clust < FAT12_ENTRY_EOC_MIN) do
  begin
    NextClust := FatGetEntry(Clust);
    FatSetEntry(Clust, FAT12_ENTRY_FREE);
    Clust := NextClust;
  end;

  FlushFAT;
  CalculateFreeSpace;
  ReadCurrentDirectory;
end;

procedure UndeleteActiveFile;
var
  Ch: Char;
  Scan: Byte;
  FirstChar: Byte;
  Clust: Word;
  NeedClusters: Word;
  I: Word;
  CanRestore: Boolean;
  Saved: PPopupSave;
begin
  if (ItemCount = 0) or (SelectedIdx < 1) or (SelectedIdx > ItemCount) then Exit;
  if not Items[SelectedIdx].IsDeleted then Exit;

  if ImageIsReadOnly then
  begin
    Saved := SaveArea(14, 9, 66, 15);
    MouseHide;
    FillBox(14, 9, 66, 15, ' ', ATTR_DIALOG_BG);
    DrawFrame(14, 9, 66, 15, ATTR_DIALOG_BD, 'Undelete File');
    WriteStr(17, 11, 'Cannot undelete: Image is read-only!', ATTR_DIALOG_HL);
    WriteStr(17, 13, 'Press any key to return...', ATTR_STATUS);
    MouseShow;
    ReadKeyBIOS(Scan);
    RestoreArea(14, 9, 66, 15, Saved);
    Exit;
  end;

  Saved := SaveArea(15, 8, 65, 14);
  FillBox(15, 8, 65, 14, ' ', ATTR_DIALOG_BG);
  DrawFrame(15, 8, 65, 14, ATTR_DIALOG_BD, 'Undelete File');
  WriteStr(17, 10, 'Restoring: ' + Items[SelectedIdx].DisplayName, ATTR_DIALOG_BG);
  WriteStr(17, 12, 'Enter first character of original filename: ', ATTR_DIALOG_HL);

  Ch := ReadKeyBIOS(Scan);
  if (Ord(Ch) < 33) or (Ord(Ch) > 126) then
  begin
    RestoreArea(15, 8, 65, 14, Saved);
    Exit;
  end;
  FirstChar := Ord(UpCase(Ch));

  { Check if start cluster is still free }
  Clust := Items[SelectedIdx].StartCluster;
  CanRestore := True;
  if Clust >= 2 then
  begin
    if FatGetEntry(Clust) <> FAT12_ENTRY_FREE then
      CanRestore := False;
  end;

  if not CanRestore then
  begin
    WriteStr(17, 13, 'Error: Original clusters have been overwritten!', ATTR_DIALOG_HL);
    ReadKeyBIOS(Scan);
    RestoreArea(15, 8, 65, 14, Saved);
    Exit;
  end;

  RestoreArea(15, 8, 65, 14, Saved);

  { Restore first char of directory entry }
  Seek(ActiveImageFile, Items[SelectedIdx].EntryOffset);
  if IOResult = 0 then
    BlockWrite(ActiveImageFile, FirstChar, 1);

  { Re-link clusters in FAT if file has a size }
  if (Items[SelectedIdx].Size > 0) and (Clust >= 2) then
  begin
    NeedClusters := (Items[SelectedIdx].Size + Layout.BytesPerCluster - 1) div Layout.BytesPerCluster;
    for I := 1 to NeedClusters do
    begin
      if I = NeedClusters then
        FatSetEntry(Clust, FAT12_ENTRY_EOC)
      else
        FatSetEntry(Clust, Clust + 1);
      Inc(Clust);
    end;
    FlushFAT;
  end;

  CalculateFreeSpace;
  ReadCurrentDirectory;
end;

procedure CreateBlankDisk;
var
  Ch: Char;
  Scan: Byte;
  NewName: TString80;
  TotalSec, SidesCount, SecPerTrk: Word;
  Saved: PPopupSave;
begin
  Saved := SaveArea(10, 6, 70, 18);
  FillBox(10, 6, 70, 18, ' ', ATTR_DIALOG_BG);
  DrawFrame(10, 6, 70, 18, ATTR_DIALOG_BD, 'Create New Blank Atari ST Disk');
  WriteStr(13, 8,  'Choose Disk Geometry:', ATTR_DIALOG_BG);
  WriteStr(13, 10, '1. Standard 720 KB (80 Trk, 2 Sides, 9 Sec)', ATTR_DIALOG_HL);
  WriteStr(13, 11, '2. Single-Sided 360 KB (80 Trk, 1 Side, 9 Sec)', ATTR_DIALOG_HL);
  WriteStr(13, 12, '3. Extended 800 KB (80 Trk, 2 Sides, 10 Sec)', ATTR_DIALOG_HL);
  WriteStr(13, 14, 'Press [1], [2], or [3] (or Esc to cancel): ', ATTR_DIALOG_BG);

  repeat
    Ch := ReadKeyBIOS(Scan);
    if Scan = KEY_F10 then Ch := #27;
    if Ch = #27 then
    begin
      RestoreArea(10, 6, 70, 18, Saved);
      Exit;
    end;
  until Ch in ['1', '2', '3'];

  case Ch of
    '1': begin SidesCount := 2; SecPerTrk := 9;  TotalSec := 1440; NewName := 'NEW720.ST'; end;
    '2': begin SidesCount := 1; SecPerTrk := 9;  TotalSec := 720;  NewName := 'NEW360.ST'; end;
    '3': begin SidesCount := 2; SecPerTrk := 10; TotalSec := 1600; NewName := 'NEW800.ST'; end;
  end;

  WriteStr(13, 16, 'Creating ' + NewName + '... Please wait.   ', ATTR_DIALOG_HL);
  RestoreArea(10, 6, 70, 18, Saved);
  if FormatBlankDisk(NewName, SidesCount, SecPerTrk, TotalSec) then
    OpenImage(NewName);
end;

{===========================================================================}
{   FILE VIEWERS & EXTERNAL GRAPHIC VIEWER (VIEW.EXE)                       }
{===========================================================================}

function ReadFileBytes(StartCluster: Word; FileSize, FileOffset: LongInt;
  var DestBuf: array of Byte; MaxBytes: Word): Word;
begin
  ReadFileBytes := ReadClusterChainBytes(ActiveImageFile, Layout.DataAreaStart,
    Layout.BytesPerCluster, @FatBuf, StartCluster, FileSize, FileOffset, DestBuf, MaxBytes);
end;

procedure InteractiveFileViewer(InitialHex: Boolean);
var
  Viewing: Boolean;
  ViewOffset, MaxOffset: LongInt;
  FileSize, PackedSize, DepackedSize, CurViewSize: LongInt;
  StartClust: Word;
  Ch: Char;
  Scan: Byte;
  Row, J: Integer;
  ReadBuf: array[0..511] of Byte;
  BytesInBuf: Word;
  HexStr, AscStr, LineStr, OffStr: string;
  B: Byte;
  RowOff, Addr: LongInt;
  Percent: Integer;
  Ratio: Integer;
  HasDepacked, IsDepackedView, DepackFileOpen: Boolean;
  DepackedPackerName: string;
  DepackF, TmpCleanupF: file;
  TargetName: TString80;
  SavedArea: PPopupSave;
  MX, MY, InEvent: Integer;
  DblClick: Boolean;

  procedure SaveCurrentDepacked;
  var
    SScan: Byte;
  begin
    if HasDepacked then
    begin
      TargetName := Items[SelectedIdx].CleanName;
      SavedArea := SaveArea(12, 10, 68, 15);
      FillBox(12, 10, 68, 15, ' ', ATTR_DIALOG_BG);
      DrawFrame(12, 10, 68, 15, ATTR_DIALOG_BD, ' Save Depacked File to DOS ');
      WriteStr(15, 12, 'Save As: ', ATTR_DIALOG_HL);
      PromptInput(24, 12, TargetName, 12);
      if TargetName <> '' then
      begin
        CopyDosFile('DEP_VIEW.$$$', TargetName);
        WriteStr(15, 13, 'Saved ' + FormatNum(DepackedSize) + ' B to ' + TargetName + '! Any key.', ATTR_DIALOG_HL);
        ReadKeyBIOS(SScan);
      end;
      RestoreArea(12, 10, 68, 15, SavedArea);
    end;
  end;

begin
  if (ItemCount = 0) or (SelectedIdx < 1) or (SelectedIdx > ItemCount) then Exit;
  if Items[SelectedIdx].IsDir then Exit;

  FileSize := Items[SelectedIdx].Size;
  PackedSize := FileSize;
  StartClust := Items[SelectedIdx].StartCluster;
  ViewOffset := 0;
  Viewing := True;
  InViewer := True;
  ViewerExitRequested := False;
  ViewerDepackToggleRequested := False;
  ViewerSaveDepackedRequested := False;

  HasDepacked := False;
  IsDepackedView := False;
  DepackFileOpen := False;
  DepackedSize := 0;
  DepackedPackerName := '';
  CurrentViewHasDepacked := False;
  CurrentViewIsDepacked := False;

  { Attempt to depack for transparent viewing }
  if ExtractSelectedFileTo('DEP_TMP.$$$') then
  begin
    if DepackUniversal('DEP_TMP.$$$', 'DEP_VIEW.$$$', DepackedPackerName, DepackedSize) then
    begin
      HasDepacked := True;
      IsDepackedView := True; { Default to depacked view }
      CurrentViewHasDepacked := True;
      CurrentViewIsDepacked := True;
      Assign(DepackF, 'DEP_VIEW.$$$');
      Reset(DepackF, 1);
      DepackFileOpen := (IOResult = 0);
    end;
  end;

  while Viewing and Running and (not ViewerExitRequested) and (ActiveImagePath <> '') do
  begin
    MouseHide;
    DrawMenuBar(0);

    if ViewerDepackToggleRequested then
    begin
      ViewerDepackToggleRequested := False;
      if HasDepacked then
        IsDepackedView := CurrentViewIsDepacked;
    end;

    if ViewerSaveDepackedRequested then
    begin
      ViewerSaveDepackedRequested := False;
      SaveCurrentDepacked;
    end;

    if IsDepackedView and HasDepacked then
      CurViewSize := DepackedSize
    else
      CurViewSize := PackedSize;

    if CurViewSize > 336 then
      MaxOffset := (CurViewSize - 336 + 15) and (not 15)
    else
      MaxOffset := 0;

    if ViewOffset > MaxOffset then ViewOffset := MaxOffset;
    if ViewOffset < 0 then ViewOffset := 0;

    if CurViewSize > 0 then
      Percent := (ViewOffset * 100) div CurViewSize
    else
      Percent := 0;

    { Interactive View Indicator Banner on Row 1 }
    if HasDepacked then
    begin
      if PackedSize > 0 then
        Ratio := 100 - Integer((PackedSize * 100) div DepackedSize)
      else
        Ratio := 0;

      if IsDepackedView then
      begin
        LineStr := ' [*DEPACKED: ' + FormatNum(DepackedSize) + ' B] [RAW: ' +
          FormatNum(PackedSize) + ' B] ' + Items[SelectedIdx].CleanName + ' (-' + IntToStr(Ratio) + '%)';
      end
      else
      begin
        LineStr := ' [ DEPACKED: ' + FormatNum(DepackedSize) + ' B] [*RAW: ' +
          FormatNum(PackedSize) + ' B] ' + Items[SelectedIdx].CleanName + ' [RAW]';
      end;
      LineStr := LineStr + ' | [D: Toggle]';
    end
    else if Items[SelectedIdx].PackerTag <> '' then
    begin
      LineStr := ' MODE: PACKED (Unsupported)| ' + Items[SelectedIdx].CleanName;
      LineStr := LineStr + ' (' + FormatNum(FileSize) + ' B, ' + Items[SelectedIdx].PackerTag + ')';
    end
    else
    begin
      LineStr := ' FILE: ' + Items[SelectedIdx].CleanName + ' (' + FormatNum(FileSize) + ' B) [UNCOMPRESSED]';
    end;
    WriteStr(0, 1, PadRight(Copy(LineStr, 1, 80), 80), ATTR_HEADER);

    { Always Uniform Hex & ASCII Columns Layout on Rows 2..23 }
    LineStr := ' Offset    00 01 02 03 04 05 06 07  08 09 0A 0B 0C 0D 0E 0F  | ASCII Text';
    WriteStr(0, 2, PadRight(LineStr, 80), ATTR_HEADER);

    if IsDepackedView and DepackFileOpen then
    begin
      Seek(DepackF, ViewOffset); BlockRead(DepackF, ReadBuf, 336, BytesInBuf);
      if IOResult <> 0 then BytesInBuf := 0;
    end
    else
    begin
      BytesInBuf := ReadFileBytes(StartClust, FileSize, ViewOffset, ReadBuf, 336);
    end;

    for Row := 0 to 20 do
    begin
      RowOff := LongInt(Row) * 16;
      if RowOff < BytesInBuf then
      begin
        Addr := ViewOffset + RowOff;
        OffStr := ' ' + HexStrWord(Addr shr 16) + HexStrWord(Addr and $FFFF) + '  ';
        HexStr := '';
        AscStr := '';
        for J := 0 to 15 do
        begin
          if RowOff + J < BytesInBuf then
          begin
            B := ReadBuf[RowOff + J];
            HexStr := HexStr + HexStrByte(B) + ' ';
            if J = 7 then HexStr := HexStr + ' ';
            if (B >= 32) and (B <= 126) then AscStr := AscStr + Chr(B) else AscStr := AscStr + '.';
          end
          else
          begin
            HexStr := HexStr + '   ';
            if J = 7 then HexStr := HexStr + ' ';
            AscStr := AscStr + ' ';
          end;
        end;
        LineStr := OffStr + HexStr + '| ' + AscStr;
        WriteStr(0, 3 + Row, PadRight(LineStr, 80), ATTR_VIEW_TXT);
      end
      else
      begin
        WriteStr(0, 3 + Row, PadRight('', 80), ATTR_VIEW_TXT);
      end;
    end;

    LineStr := ' Pos: ' + FormatNum(ViewOffset) + ' / ' + FormatNum(CurViewSize) + ' B (' +
      IntToStr(Percent) + '%)';
    if HasDepacked then
    begin
      if IsDepackedView then
        LineStr := PadRight(Copy(LineStr, 1, 34), 34) + '[D] View RAW PACKED | [S] Save | Esc: Close'
      else
        LineStr := PadRight(Copy(LineStr, 1, 34), 34) + '[D] View DEPACKED   | [S] Save | Esc: Close';
    end
    else
    begin
      LineStr := PadRight(Copy(LineStr, 1, 38), 38) + '[E] Extract  |  F10: Menu  |  Esc: Close';
    end;
    WriteStr(0, 24, PadRight(Copy(LineStr, 1, 80), 80), ATTR_STATUS);
    MouseShow;

    InEvent := GetInputEvent(Ch, Scan, MX, MY, DblClick);

    if InEvent = EVENT_CLICK then
    begin
      if MY = 0 then
      begin
        { Clicked on top Menu Bar }
        if (MX >= MenuX[3]) and (MX <= MenuX[3] + 7) then
          ExecuteDropdownMenu(3)
        else if (MX >= MenuX[1]) and (MX <= MenuX[1] + 7) then
          ExecuteDropdownMenu(1)
        else if (MX >= MenuX[2]) and (MX <= MenuX[2] + 8) then
          ExecuteDropdownMenu(2)
        else if (MX >= MenuX[4]) and (MX <= MenuX[4] + 7) then
          ExecuteDropdownMenu(4);

        if CurrentViewHasDepacked then
          IsDepackedView := CurrentViewIsDepacked;
      end
      else if MY = 1 then
      begin
        { Clicked on Row 1 tab banner to toggle }
        if CurrentViewHasDepacked then
        begin
          IsDepackedView := not IsDepackedView;
          CurrentViewIsDepacked := IsDepackedView;
        end;
      end
      else if MY = 24 then
      begin
        { Clicked on Row 24 action buttons }
        if MX < 25 then
        begin
          if CurrentViewHasDepacked then
          begin
            IsDepackedView := not IsDepackedView;
            CurrentViewIsDepacked := IsDepackedView;
          end;
        end
        else if (MX >= 25) and (MX < 45) then
        begin
          SaveCurrentDepacked;
        end
        else if (MX >= 45) and (MX < 60) then
        begin
          ExtractActiveFile;
        end
        else if MX >= 60 then
        begin
          Viewing := False;
        end;
      end;
    end
    else if Ch = #0 then
    begin
      case Scan of
        KEY_UP:
          begin
            if ViewOffset >= 16 then Dec(ViewOffset, 16) else ViewOffset := 0;
          end;
        KEY_DOWN:
          begin
            if ViewOffset + 16 <= MaxOffset then Inc(ViewOffset, 16);
          end;
        KEY_PAGEUP:
          begin
            if ViewOffset >= 336 then Dec(ViewOffset, 336) else ViewOffset := 0;
          end;
        KEY_PAGEDOWN:
          begin
            if ViewOffset + 336 <= MaxOffset then Inc(ViewOffset, 336) else ViewOffset := MaxOffset;
          end;
        KEY_HOME: ViewOffset := 0;
        KEY_END: ViewOffset := MaxOffset;
        KEY_F5: ExtractActiveFile;
        KEY_F10, KEY_ALT_V:
          begin
            ExecuteDropdownMenu(3);
            if CurrentViewHasDepacked then IsDepackedView := CurrentViewIsDepacked;
          end;
        KEY_ALT_F:
          begin
            ExecuteDropdownMenu(1);
            if CurrentViewHasDepacked then IsDepackedView := CurrentViewIsDepacked;
          end;
        KEY_ALT_I:
          begin
            ExecuteDropdownMenu(2);
            if CurrentViewHasDepacked then IsDepackedView := CurrentViewIsDepacked;
          end;
        KEY_ALT_H:
          begin
            ExecuteDropdownMenu(4);
            if CurrentViewHasDepacked then IsDepackedView := CurrentViewIsDepacked;
          end;
        KEY_ALT_R:
          ShowRenameModal;
        KEY_ALT_A:
          ShowAttrModal;
        KEY_ALT_C:
          ShowCatalogModal;
        KEY_ALT_X:
          begin
            Viewing := False;
            Running := False;
          end;
      end;
    end
    else
    begin
      case UpCase(Ch) of
        #27, 'Q': Viewing := False;
        'D':
          begin
            if HasDepacked then
            begin
              IsDepackedView := not IsDepackedView;
              CurrentViewIsDepacked := IsDepackedView;
            end;
          end;
        'S': SaveCurrentDepacked;
        'E': ExtractActiveFile;
        'V', 'H', 'T': ; { Kept for compatibility }
        'F':
          begin
            ExecuteDropdownMenu(1);
            if CurrentViewHasDepacked then IsDepackedView := CurrentViewIsDepacked;
          end;
      end;
    end;
  end;

  if DepackFileOpen then
  begin
    Close(DepackF);
    DepackFileOpen := False;
  end;
  if IOResult <> 0 then ;
  Assign(TmpCleanupF, 'DEP_TMP.$$$'); Erase(TmpCleanupF);
  if IOResult <> 0 then ;
  Assign(TmpCleanupF, 'DEP_VIEW.$$$'); Erase(TmpCleanupF);
  if IOResult <> 0 then ;

  InViewer := False;
  FillBox(0, 0, 79, 24, ' ', ATTR_NORMAL);
end;

procedure ViewFileText;
begin
  InteractiveFileViewer(False);
end;

procedure ViewFileHex;
begin
  InteractiveFileViewer(True);
end;

procedure DepackActiveFile(ViewMode: Boolean);
var
  TargetName: TString80;
  Ext: string[4];
  I: Integer;
  Saved: PPopupSave;
  Ch: Char;
  Scan: Byte;
  PackTag: string[16];
  DepackedSize: LongInt;
  DepackedName: string;
  Success: Boolean;
  Ratio: Integer;
  TmpCleanupF: file;
begin
  if (ItemCount = 0) or (SelectedIdx < 1) or (SelectedIdx > ItemCount) then Exit;
  if Items[SelectedIdx].IsDir then Exit;

  PackTag := Items[SelectedIdx].PackerTag;
  if PackTag = '' then PackTag := 'None / Raw';

  { Step 1: Extract active file to temporary file }
  if not ExtractSelectedFileTo('DEP_TMP.$$$') then Exit;

  { Step 2: Attempt universal depacking }
  Success := DepackUniversal('DEP_TMP.$$$', 'DEP_VIEW.$$$', DepackedName, DepackedSize);

  { If it is a picture and ViewMode requested, view immediately }
  if ViewMode and Success and (Pos('PC', DepackedName) > 0) then
  begin
    if Pos('PC2', DepackedName) > 0 then
      CopyDosFile('DEP_VIEW.$$$', 'ST_VIEW.PI2')
    else if Pos('PC3', DepackedName) > 0 then
      CopyDosFile('DEP_VIEW.$$$', 'ST_VIEW.PI3')
    else
      CopyDosFile('DEP_VIEW.$$$', 'ST_VIEW.PI1');
    ViewImageGraphic;
    if IOResult <> 0 then ;
    Assign(TmpCleanupF, 'DEP_TMP.$$$'); Erase(TmpCleanupF);
    if IOResult <> 0 then ;
    Assign(TmpCleanupF, 'DEP_VIEW.$$$'); Erase(TmpCleanupF);
    if IOResult <> 0 then ;
    Exit;
  end;

  Saved := SaveArea(10, 7, 70, 18);
  FillBox(10, 7, 70, 18, ' ', ATTR_DIALOG_BG);
  DrawFrame(10, 7, 70, 18, ATTR_DIALOG_BD, 'Atari ST Depack & Extraction Manager');

  WriteStr(13, 9,  'Selected File:    ' + Items[SelectedIdx].CleanName, ATTR_DIALOG_BG);
  WriteStr(13, 10, 'Packed Size:      ' + FormatNum(Items[SelectedIdx].Size) + ' bytes', ATTR_DIALOG_BG);

  if Success then
  begin
    if Items[SelectedIdx].Size > 0 then
      Ratio := 100 - Integer((Items[SelectedIdx].Size * 100) div DepackedSize)
    else
      Ratio := 0;
    WriteStr(13, 11, 'Detected Packer:  ' + DepackedName + ' (Depacked OK)', ATTR_DIALOG_HL);
    WriteStr(13, 12, 'Depacked Size:    ' + FormatNum(DepackedSize) +
      ' bytes (-' + IntToStr(Ratio) + '%)', ATTR_DIALOG_HL);

    TargetName := Items[SelectedIdx].CleanName;
    if Pos('PC1', DepackedName) > 0 then
      TargetName := Copy(Items[SelectedIdx].CleanName, 1, Length(Items[SelectedIdx].CleanName) - 4) + '.PI1'
    else if Pos('PC2', DepackedName) > 0 then
      TargetName := Copy(Items[SelectedIdx].CleanName, 1, Length(Items[SelectedIdx].CleanName) - 4) + '.PI2'
    else if Pos('PC3', DepackedName) > 0 then
      TargetName := Copy(Items[SelectedIdx].CleanName, 1, Length(Items[SelectedIdx].CleanName) - 4) + '.PI3';

    WriteStr(13, 14, '[Enter] Extract Depacked  [E] Raw  [V] View  [Esc] Exit', ATTR_HEADER);

    repeat
      Ch := ReadKeyBIOS(Scan);
      case UpCase(Ch) of
        #13:
          begin
            WriteStr(13, 14, PadRight('Save As: ', 55), ATTR_DIALOG_BG);
            WriteStr(13, 14, 'Save As: ', ATTR_DIALOG_HL);
            PromptInput(22, 14, TargetName, 12);
            if TargetName <> '' then
            begin
              CopyDosFile('DEP_VIEW.$$$', TargetName);
              WriteStr(13, 16, 'Saved ' + FormatNum(DepackedSize) +
                ' B to ' + TargetName + '! Any key.', ATTR_DIALOG_HL);
              ReadKeyBIOS(Scan);
            end;
            Break;
          end;
        'V':
          begin
            RestoreArea(10, 7, 70, 18, Saved);
            InteractiveFileViewer(True);
            Exit;
          end;
        'E':
          begin
            RestoreArea(10, 7, 70, 18, Saved);
            ExtractActiveFile;
            Exit;
          end;
        #27: Break;
      end;
    until False;
  end
  else
  begin
    WriteStr(13, 11, 'Packer Status:    File is not packed or raw data', ATTR_STATUS);
    WriteStr(13, 14, '[E] Extract Raw File   [V] View File   [Esc] Cancel', ATTR_HEADER);
    repeat
      Ch := ReadKeyBIOS(Scan);
      case UpCase(Ch) of
        'E':
          begin
            RestoreArea(10, 7, 70, 18, Saved);
            ExtractActiveFile;
            Exit;
          end;
        'V':
          begin
            RestoreArea(10, 7, 70, 18, Saved);
            InteractiveFileViewer(True);
            Exit;
          end;
        #27: Break;
      end;
    until False;
  end;

  RestoreArea(10, 7, 70, 18, Saved);
  if IOResult <> 0 then ;
  Assign(TmpCleanupF, 'DEP_TMP.$$$'); Erase(TmpCleanupF);
  if IOResult <> 0 then ;
  Assign(TmpCleanupF, 'DEP_VIEW.$$$'); Erase(TmpCleanupF);
  if IOResult <> 0 then ;
end;

{ Extracts file to temporary storage and executes VIEW.EXE }
procedure ViewImageGraphic;
var
  TargetName: TString80;
  Ext: string[4];
  I: Integer;
  SrcF: file;
  Scan: Byte;
  PackerName: string;
  DepackedSize: LongInt;
  Success, NeedDepack: Boolean;
  Regs: Registers;
  IsGraphic: Boolean;
  ViewProg: TString80;
begin
  if (ItemCount = 0) or (SelectedIdx < 1) or (SelectedIdx > ItemCount) then Exit;
  if Items[SelectedIdx].IsDir then Exit;
  if IOResult <> 0 then ;

  if not ResolveHelperExe('VIEW.EXE', AppDir, ViewProg) then
  begin
    FillBox(14, 9, 66, 13, ' ', ATTR_DIALOG_BG);
    DrawFrame(14, 9, 66, 13, ATTR_DIALOG_BD, 'Image Viewer');
    WriteStr(16, 11, 'Error: VIEW.EXE not found in ' + Copy(AppDir, 1, 23), ATTR_DIALOG_HL);
    ReadKeyBIOS(Scan);
    Exit;
  end;

  Ext := '';
  I := Length(Items[SelectedIdx].CleanName);
  while (I > 1) and (Items[SelectedIdx].CleanName[I] <> '.') do Dec(I);
  if (I > 1) and (Items[SelectedIdx].CleanName[I] = '.') then
    Ext := Copy(Items[SelectedIdx].CleanName, I, Length(Items[SelectedIdx].CleanName) - I + 1);
  for I := 1 to Length(Ext) do Ext[I] := UpCase(Ext[I]);

  IsGraphic := (Ext = '.PI1') or (Ext = '.PI2') or (Ext = '.PI3') or
               (Ext = '.PC1') or (Ext = '.PC2') or (Ext = '.PC3') or
               (Ext = '.NEO') or (Ext = '.DEG') or (Ext = '.ART') or
               (Ext = '.DOO') or (Ext = '.SCR') or (Ext = '.PAC') or
               (Ext = '.BMP') or (Ext = '.GIF') or (Ext = '.JPG');

  if not IsGraphic then
  begin
    FillBox(15, 9, 65, 13, ' ', ATTR_DIALOG_BG);
    DrawFrame(15, 9, 65, 13, ATTR_DIALOG_BD, 'Image Viewer');
    WriteStr(17, 11, 'Not a supported graphic format (' + Ext + ')', ATTR_DIALOG_HL);
    ReadKeyBIOS(Scan);
    Exit;
  end;

  TargetName := 'ST_VIEW' + Ext;
  NeedDepack := (Ext = '.PC1') or (Ext = '.PC2') or (Ext = '.PC3') or
                (Ext = '.PAC') or (Items[SelectedIdx].PackerTag <> '') or
                (((Ext = '.PI1') or (Ext = '.PI2') or (Ext = '.PI3')) and
                 (Items[SelectedIdx].Size < 32034)) or
                ((Ext = '.NEO') and (Items[SelectedIdx].Size < 32128));

  if NeedDepack then
  begin
    if (Ext = '.PC2') or (Ext = '.PI2') then
      TargetName := 'ST_VIEW.PI2'
    else if (Ext = '.PC3') or (Ext = '.PI3') then
      TargetName := 'ST_VIEW.PI3'
    else if (Ext = '.PC1') or (Ext = '.PI1') or (Ext = '.PAC') then
      TargetName := 'ST_VIEW.PI1';

    if not ExtractSelectedFileTo('DEP_TMP.$$$') then
    begin
      Assign(SrcF, 'DEP_TMP.$$$'); Erase(SrcF);
      if IOResult <> 0 then ;
      FillBox(15, 9, 65, 13, ' ', ATTR_DIALOG_BG);
      DrawFrame(15, 9, 65, 13, ATTR_DIALOG_BD, 'Image Viewer');
      WriteStr(17, 11, 'Error: Failed to extract graphic file!', ATTR_DIALOG_HL);
      ReadKeyBIOS(Scan);
      Exit;
    end;
    Success := DepackUniversal('DEP_TMP.$$$', TargetName, PackerName, DepackedSize);
    Assign(SrcF, 'DEP_TMP.$$$'); Erase(SrcF);
    if IOResult <> 0 then ;
    if not Success then
    begin
      TargetName := 'ST_VIEW' + Ext;
      { Fallback: extract compressed file directly for VIEW.EXE to decode }
      if not ExtractSelectedFileTo(TargetName) then
      begin
        FillBox(15, 9, 65, 13, ' ', ATTR_DIALOG_BG);
        DrawFrame(15, 9, 65, 13, ATTR_DIALOG_BD, 'Image Viewer');
        WriteStr(17, 11, 'Error: Failed to extract graphic file!', ATTR_DIALOG_HL);
        ReadKeyBIOS(Scan);
        Exit;
      end;
    end;
  end
  else
  begin
    if not ExtractSelectedFileTo(TargetName) then
    begin
      FillBox(15, 9, 65, 13, ' ', ATTR_DIALOG_BG);
      DrawFrame(15, 9, 65, 13, ATTR_DIALOG_BD, 'Image Viewer');
      WriteStr(17, 11, 'Error: Failed to extract graphic file!', ATTR_DIALOG_HL);
      ReadKeyBIOS(Scan);
      Exit;
    end;
  end;

  { Flush keyboard buffer before launching viewer }
  while KeyWaiting do ReadKeyBIOS(Scan);

  { Execute VIEW.EXE }
  SafeExec(ViewProg, TargetName);

  { Restore video mode 3 (80x25 color text) }
  Regs.AX := $0003;
  Intr($10, Regs);
  HideCursor;

  if (DosError <> 0) or (DosExitCode <> 0) then
  begin
    FillBox(14, 9, 66, 13, ' ', ATTR_DIALOG_BG);
    DrawFrame(14, 9, 66, 13, ATTR_DIALOG_BD, 'Image Viewer');
    if DosError <> 0 then
      WriteStr(16, 11, 'Exec failed (DosError ' + IntToStr(DosError) + ')', ATTR_DIALOG_HL)
    else
      WriteStr(16, 11, 'Viewer failed to open or decode image', ATTR_DIALOG_HL);
    ReadKeyBIOS(Scan);
  end;

  { Purge temporary files }
  if IOResult <> 0 then ;
  Assign(SrcF, TargetName); Erase(SrcF);
  if IOResult <> 0 then ;
  Assign(SrcF, 'ST_VIEW.PI1'); Erase(SrcF);
  if IOResult <> 0 then ;
  Assign(SrcF, 'ST_VIEW.PI2'); Erase(SrcF);
  if IOResult <> 0 then ;
  Assign(SrcF, 'ST_VIEW.PI3'); Erase(SrcF);
  if IOResult <> 0 then ;
  Assign(SrcF, 'DEP_TMP.$$$'); Erase(SrcF);
  if IOResult <> 0 then ;
  Assign(SrcF, 'DEP_VIEW.$$$'); Erase(SrcF);
  if IOResult <> 0 then ;

  { Flush keyboard buffer after return }
  while KeyWaiting do ReadKeyBIOS(Scan);

  FillBox(0, 0, 79, 24, ' ', ATTR_NORMAL);
  RenderScreen;
end;

{===========================================================================}
{   DROP-DOWN MENU SYSTEM (ROW 0)                                           }
{===========================================================================}

const
  FILE_ITEMS_COUNT = 16;
  FileItems: array[1..FILE_ITEMS_COUNT] of string[28] = (
    ' Open Image...          O   ',
    ' New Blank Disk...      F9  ',
    ' Close Image            C   ',
    '----------------------------',
    ' Import File to Disk... I   ',
    ' Create Subfolder...    F7  ',
    ' Rename Item...        Alt+R',
    ' File Attributes...    Alt+A',
    '----------------------------',
    ' Extract File to DOS... F5  ',
    ' Extract & Depack...    P   ',
    ' Extract All as ZIP...  Z   ',
    ' Delete File / Folder   F8  ',
    ' Undelete File (*d*)    U   ',
    '----------------------------',
    ' Exit to DOS           Alt+X'
  );

  IMAGE_ITEMS_COUNT = 12;
  ImageItems: array[1..IMAGE_ITEMS_COUNT] of string[28] = (
    ' Search Files (Wild)    F   ',
    ' Export Catalog (CSV)   X   ',
    '----------------------------',
    ' Disk Geometry / BPB    F2  ',
    ' Boot Sector Hex View   B   ',
    ' Virus Scanner...       S   ',
    ' Visual Cluster Map...  M   ',
    ' Write Image to Floppy  W   ',
    ' Read Floppy to Image   L   ',
    ' Make PC-Compatible     K   ',
    '----------------------------',
    ' Refresh Directory      R   '
  );

  VIEW_ITEMS_COUNT = 4;
  ViewItems: array[1..VIEW_ITEMS_COUNT] of string[28] = (
    ' View File (Hex+ASCII)  V   ',
    ' Visual Cluster Map...  M   ',
    ' Graphic (VIEW.EXE)    Alt+V',
    ' Extract & Depack...    P   '
  );

  HELP_ITEMS_COUNT = 2;
  HelpItems: array[1..HELP_ITEMS_COUNT] of string[28] = (
    ' Keyboard Shortcuts     F1  ',
    ' About STIMAGE DOS      A   '
  );

procedure DrawMenuBar(ActiveMenu: Integer);
var
  M: Integer;
begin
  WriteStr(0, 0, PadRight('', 80), ATTR_MENU_BAR);
  for M := 1 to MENU_MAX do
  begin
    if M = ActiveMenu then
      WriteStr(MenuX[M], 0, MenuNames[M], ATTR_MENU_ACT)
    else
    begin
      WriteStr(MenuX[M], 0, MenuNames[M], ATTR_MENU_BAR);
      WriteCell(MenuX[M] + 1, 0, MenuNames[M][2], ATTR_MENU_HOT);
    end;
  end;
  WriteStr(40, 0, APP_TITLE, ATTR_MENU_BAR);
end;

procedure ExecuteDropdownMenu(InitialMenu: Integer);
var
  CurMenu, CurItem, MaxItems: Integer;
  Ch: Char;
  Scan: Byte;
  Saved: PPopupSave;
  BoxX1, BoxY1, BoxX2, BoxY2: Integer;
  I: Integer;
  Attr: Byte;
  PickedFile: string;
  MX, MY, InEvent: Integer;
  DblClick: Boolean;
begin
  CurMenu := InitialMenu;
  CurItem := 1;

  repeat
    DrawMenuBar(CurMenu);

    if InViewer and (CurMenu = 3) then
      MaxItems := 5
    else
      case CurMenu of
        1: MaxItems := FILE_ITEMS_COUNT;
        2: MaxItems := IMAGE_ITEMS_COUNT;
        3: MaxItems := VIEW_ITEMS_COUNT;
        4: MaxItems := HELP_ITEMS_COUNT;
      end;

    BoxX1 := MenuX[CurMenu];
    BoxY1 := 1;
    BoxX2 := BoxX1 + 30;
    BoxY2 := BoxY1 + MaxItems + 1;

    Saved := SaveArea(BoxX1, BoxY1, BoxX2, BoxY2);

    FillBox(BoxX1, BoxY1, BoxX2, BoxY2, ' ', ATTR_MENU_BOX);
    DrawFrame(BoxX1, BoxY1, BoxX2, BoxY2, ATTR_MENU_BD, '');

    for I := 1 to MaxItems do
    begin
      if I = CurItem then
        Attr := ATTR_MENU_SEL
      else
        Attr := ATTR_MENU_BOX;

      case CurMenu of
        1: WriteStr(BoxX1 + 1, BoxY1 + I, FileItems[I], Attr);
        2: WriteStr(BoxX1 + 1, BoxY1 + I, ImageItems[I], Attr);
        3:
          if InViewer then
          begin
            if CurrentViewHasDepacked then
            begin
              case I of
                1:
                  if CurrentViewIsDepacked then
                    WriteStr(BoxX1 + 1, BoxY1 + I, ' [*] View DEPACKED Data D   ', Attr)
                  else
                    WriteStr(BoxX1 + 1, BoxY1 + I, ' [ ] View DEPACKED Data D   ', Attr);
                2:
                  if not CurrentViewIsDepacked then
                    WriteStr(BoxX1 + 1, BoxY1 + I, ' [*] View RAW PACKED    D   ', Attr)
                  else
                    WriteStr(BoxX1 + 1, BoxY1 + I, ' [ ] View RAW PACKED    D   ', Attr);
                3: WriteStr(BoxX1 + 1, BoxY1 + I, '----------------------------', Attr);
                4: WriteStr(BoxX1 + 1, BoxY1 + I, ' Save Depacked to DOS   S   ', Attr);
                5: WriteStr(BoxX1 + 1, BoxY1 + I, ' Close Viewer           Esc ', Attr);
              end;
            end
            else
            begin
              case I of
                1: WriteStr(BoxX1 + 1, BoxY1 + I, ' [*] View RAW File Data     ', Attr);
                2: WriteStr(BoxX1 + 1, BoxY1 + I, ' [ ] Depacked Data (N/A)    ', Attr);
                3: WriteStr(BoxX1 + 1, BoxY1 + I, '----------------------------', Attr);
                4: WriteStr(BoxX1 + 1, BoxY1 + I, ' Save File to DOS       S   ', Attr);
                5: WriteStr(BoxX1 + 1, BoxY1 + I, ' Close Viewer           Esc ', Attr);
              end;
            end;
          end
          else
            WriteStr(BoxX1 + 1, BoxY1 + I, ViewItems[I], Attr);
        4: WriteStr(BoxX1 + 1, BoxY1 + I, HelpItems[I], Attr);
      end;
    end;
    MouseShow;

    InEvent := GetInputEvent(Ch, Scan, MX, MY, DblClick);
    MouseHide;
    RestoreArea(BoxX1, BoxY1, BoxX1 + 30, BoxY1 + MaxItems + 1, Saved);

    if InEvent = EVENT_CLICK then
    begin
      { Mouse click inside or outside menu }
      if MY = 0 then
      begin
        { Clicked another menu on Row 0 }
        if (MX >= MenuX[1]) and (MX <= MenuX[1] + 7) then
        begin CurMenu := 1; CurItem := 1; Continue; end
        else if (MX >= MenuX[2]) and (MX <= MenuX[2] + 8) then
        begin CurMenu := 2; CurItem := 1; Continue; end
        else if (MX >= MenuX[3]) and (MX <= MenuX[3] + 7) then
        begin CurMenu := 3; CurItem := 1; Continue; end
        else if (MX >= MenuX[4]) and (MX <= MenuX[4] + 7) then
        begin CurMenu := 4; CurItem := 1; Continue; end
        else Exit;
      end
      else if (MX >= BoxX1) and (MX <= BoxX1 + 30) and
              (MY >= BoxY1 + 1) and (MY <= BoxY1 + MaxItems) then
      begin
        CurItem := MY - BoxY1;
        { If clicked separator, ignore }
        if (CurMenu = 1) and ((CurItem = 4) or (CurItem = 9) or (CurItem = 15)) then Continue;
        if (CurMenu = 2) and ((CurItem = 3) or (CurItem = 10)) then Continue;
        if (CurMenu = 3) and InViewer and (CurItem = 3) then Continue;
        Ch := #13; { Simulate Enter }
      end
      else
      begin
        { Clicked outside menu box: close menu }
        Exit;
      end;
    end;

    if Ch = #0 then
    begin
      case Scan of
        KEY_LEFT:
          begin
            Dec(CurMenu);
            if CurMenu < 1 then CurMenu := MENU_MAX;
            CurItem := 1;
          end;
        KEY_RIGHT:
          begin
            Inc(CurMenu);
            if CurMenu > MENU_MAX then CurMenu := 1;
            CurItem := 1;
          end;
        KEY_UP:
          begin
            repeat
              Dec(CurItem);
              if CurItem < 1 then CurItem := MaxItems;
            until not (((CurMenu = 1) and ((CurItem = 4) or (CurItem = 9) or (CurItem = 15))) or
                      ((CurMenu = 2) and ((CurItem = 3) or (CurItem = 10))) or
                      ((CurMenu = 3) and InViewer and (CurItem = 3)));
          end;
        KEY_DOWN:
          begin
            repeat
              Inc(CurItem);
              if CurItem > MaxItems then CurItem := 1;
            until not (((CurMenu = 1) and ((CurItem = 4) or (CurItem = 9) or (CurItem = 15))) or
                      ((CurMenu = 2) and ((CurItem = 3) or (CurItem = 10))) or
                      ((CurMenu = 3) and InViewer and (CurItem = 3)));
          end;
        KEY_F1:  begin CurMenu := 4; CurItem := 1; Ch := #13; end;
        KEY_F2:  begin CurMenu := 2; CurItem := 4; Ch := #13; end;
        KEY_F3, KEY_F4:  begin CurMenu := 3; CurItem := 1; Ch := #13; end;
        KEY_F5:  begin CurMenu := 1; CurItem := 10; Ch := #13; end;
        KEY_F6:  begin CurMenu := 2; CurItem := 7; Ch := #13; end;
        KEY_F8:  begin CurMenu := 1; CurItem := 13; Ch := #13; end;
        KEY_F7:
          ShowMkdirModal;
        KEY_F9:  begin CurMenu := 1; CurItem := 2; Ch := #13; end;
        KEY_F10: Exit;
      end;
    end
    else
    begin
      if (Ch = #27) then Exit;

      if (Ch <> #13) then
      begin
        case CurMenu of
          1: { File }
            case UpCase(Ch) of
              'O': begin CurItem := 1; Ch := #13; end;
              'N': begin CurItem := 2; Ch := #13; end;
              'C': begin CurItem := 3; Ch := #13; end;
              'I': begin CurItem := 5; Ch := #13; end;
              'M', '+': begin CurItem := 6; Ch := #13; end;
              'R': begin CurItem := 7; Ch := #13; end;
              'A': begin CurItem := 8; Ch := #13; end;
              'E': begin CurItem := 10; Ch := #13; end;
              'P': begin CurItem := 11; Ch := #13; end;
              'Z': begin CurItem := 12; Ch := #13; end;
              'D': begin CurItem := 13; Ch := #13; end;
              'U': begin CurItem := 14; Ch := #13; end;
              'X', 'Q': begin CurItem := 16; Ch := #13; end;
            end;
          2: { Image }
            case UpCase(Ch) of
              'F': begin CurItem := 1; Ch := #13; end;
              'X', 'E': begin CurItem := 2; Ch := #13; end;
              'G': begin CurItem := 4; Ch := #13; end;
              'B': begin CurItem := 5; Ch := #13; end;
              'S': begin CurItem := 6; Ch := #13; end;
              'M': begin CurItem := 7; Ch := #13; end;
              'W': begin CurItem := 8; Ch := #13; end;
              'L': begin CurItem := 9; Ch := #13; end;
              'K': begin CurItem := 10; Ch := #13; end;
              'R': begin CurItem := 12; Ch := #13; end;
            end;
          3: { View }
            if InViewer then
              case UpCase(Ch) of
                'D': begin
                       if CurrentViewHasDepacked then
                       begin
                         if CurrentViewIsDepacked then CurItem := 2 else CurItem := 1;
                         Ch := #13;
                       end;
                     end;
                'S': begin CurItem := 4; Ch := #13; end;
                'C', 'X', 'Q': begin CurItem := 5; Ch := #13; end;
              end
            else
              case UpCase(Ch) of
                'V', 'H', 'T': begin CurItem := 1; Ch := #13; end;
                'M': begin CurItem := 2; Ch := #13; end;
                'G': begin CurItem := 3; Ch := #13; end;
                'P': begin CurItem := 4; Ch := #13; end;
              end;
          4: { Help }
            case UpCase(Ch) of
              'H', '?': begin CurItem := 1; Ch := #13; end;
              'A': begin CurItem := 2; Ch := #13; end;
            end;
        end;
      end;

      if Ch = #13 then
      begin
        DrawMenuBar(0);
        case CurMenu of
          1: { File Menu }
            case CurItem of
              1:
                begin
                  if ShowFileDialog(PickedFile) then
                  begin
                    OpenImage(PickedFile);
                    if InViewer then ViewerExitRequested := True;
                  end;
                  Exit;
                end;
              2:
                begin
                  CreateBlankDisk;
                  if InViewer then ViewerExitRequested := True;
                  Exit;
                end;
              3:
                begin
                  CloseImage;
                  if InViewer then ViewerExitRequested := True;
                  Exit;
                end;
              5: begin ShowImportFileModal; Exit; end;
              6: begin ShowMkdirModal; Exit; end;
              7: begin ShowRenameModal; Exit; end;
              8: begin ShowAttrModal; Exit; end;
              10: begin ExtractActiveFile; Exit; end;
              11: begin DepackActiveFile(False); Exit; end;
              12: begin ExtractAllAsZip; Exit; end;
              13:
                begin
                  DeleteActiveFile;
                  if InViewer then ViewerExitRequested := True;
                  Exit;
                end;
              14: begin UndeleteActiveFile; Exit; end;
              16:
                begin
                  Running := False;
                  if InViewer then ViewerExitRequested := True;
                  Exit;
                end;
            end;
          2: { Image Menu }
            case CurItem of
              1: begin ShowSearchModal; Exit; end;
              2: begin ShowCatalogModal; Exit; end;
              4: begin ShowBPBModal; Exit; end;
              5: begin ShowBootSectorHexModal; Exit; end;
              6: begin ShowVirusScannerModal; Exit; end;
              7: begin ShowClusterMapModal; Exit; end;
              8: begin WriteImageToFloppyModal; Exit; end;
              9: begin ReadFloppyToImageModal; Exit; end;
              10: begin MakeDiskPCCompatibleModal; Exit; end;
              12: begin ReadCurrentDirectory; Exit; end;
            end;
          3: { View Menu }
            if InViewer then
            begin
              case CurItem of
                1:
                  begin
                    if CurrentViewHasDepacked then
                    begin
                      CurrentViewIsDepacked := True;
                      ViewerDepackToggleRequested := True;
                    end;
                    Exit;
                  end;
                2:
                  begin
                    if CurrentViewHasDepacked then
                    begin
                      CurrentViewIsDepacked := False;
                      ViewerDepackToggleRequested := True;
                    end;
                    Exit;
                  end;
                4:
                  begin
                    ViewerSaveDepackedRequested := True;
                    Exit;
                  end;
                5:
                  begin
                    ViewerExitRequested := True;
                    Exit;
                  end;
              end;
            end
            else
            begin
              case CurItem of
                1: begin InteractiveFileViewer(True); Exit; end;
                2: begin ShowClusterMapModal; Exit; end;
                3: begin ViewImageGraphic; Exit; end;
                4: begin DepackActiveFile(False); Exit; end;
              end;
            end;
          4: { Help Menu }
            case CurItem of
              1: begin ShowHelpModal; Exit; end;
              2: begin ShowAboutModal; Exit; end;
            end;
        end;
      end;
    end;
  until False;
end;

{===========================================================================}
{   MODAL POPUPS (CLUSTER MAP, WRITE FLOPPY, BPB, HELP, ABOUT)              }
{===========================================================================}

procedure ShowClusterMapModal;
var
  Saved: PPopupSave;
  MaxClust: Word;
  CurClust: Word;
  SelFileClusters: array[0..360] of Byte;
  HasPred: array[0..360] of Byte;
  IsSel, HasP: Boolean;
  Clust: Word;
  Row, Col: Integer;
  GridX, GridY: Integer;
  Event: Integer;
  Ch: Char;
  Scan: Byte;
  MX, MY: Integer;
  DblClick: Boolean;
  OwnerName: TString12;
  ChainPos, ChainLen: Integer;
  IsSelOwner: Boolean;
  PhysSec, SecsPerCyl, Cyl, Head, Sec: LongInt;
  ByteOff: LongInt;
  FatVal: Word;
  StatusStr: string[30];
  NextStr: string[12];
  C: Word;
  Attr: Byte;
  Chr: Char;
  RowBase: Word;
  ClickedClust: Word;
  LineStr: string;
begin
  if (not ImageIsOpen) or (Layout.TotalClusters = 0) then Exit;

  MaxClust := Layout.TotalClusters;
  CurClust := 2;
  if (SelectedIdx >= 1) and (SelectedIdx <= ItemCount) and (Items[SelectedIdx].StartCluster >= 2) then
    CurClust := Items[SelectedIdx].StartCluster;

  FillChar(SelFileClusters, SizeOf(SelFileClusters), 0);
  if (SelectedIdx >= 1) and (SelectedIdx <= ItemCount) and (not Items[SelectedIdx].IsDir) then
  begin
    Clust := Items[SelectedIdx].StartCluster;
    while (Clust >= 2) and (Clust < FAT12_ENTRY_EOC_MIN) and (Clust <= MaxClust + 1) do
    begin
      SelFileClusters[Clust shr 3] := SelFileClusters[Clust shr 3] or (1 shl (Clust and 7));
      Clust := FatGetEntry(Clust);
    end;
    if (Clust >= 2) and (Clust <= MaxClust + 1) then
      SelFileClusters[Clust shr 3] := SelFileClusters[Clust shr 3] or (1 shl (Clust and 7));
  end;

  FillChar(HasPred, SizeOf(HasPred), 0);
  for Clust := 2 to MaxClust + 1 do
  begin
    FatVal := FatGetEntry(Clust);
    if (FatVal >= 2) and (FatVal <= MaxClust + 1) then
      HasPred[FatVal shr 3] := HasPred[FatVal shr 3] or (1 shl (FatVal and 7));
  end;

  Saved := SaveArea(1, 1, 78, 23);
  MouseHide;
  FillBox(1, 1, 78, 23, ' ', ATTR_DIALOG_BG);
  DrawFrame(1, 1, 78, 23, ATTR_DIALOG_BD, ' Atari ST Disk Cluster Allocation Map ');

  LineStr := 'Disk: ' + Copy(ActiveImagePath, 1, 24) + ' | ' +
    IntToStr(Layout.Sides) + ' Sides, ' + IntToStr(Layout.Tracks) + ' Trk, ' +
    IntToStr(Layout.SectorsPerTrack) + ' SPT | ' + IntToStr(Layout.BytesPerCluster) + ' B/Clu';
  WriteStr(3, 2, PadRight(Copy(LineStr, 1, 74), 74), ATTR_DIALOG_HL);

  for Row := 0 to 14 do
  begin
    RowBase := 2 + (Row * 60);
    WriteStr(3, 4 + Row, 'Clu ' + PadLeft(IntToStr(RowBase), 4) + ':', ATTR_DIALOG_BG);
  end;
  MouseShow;

  repeat
    MouseHide;
    for Row := 0 to 14 do
    begin
      for Col := 0 to 59 do
      begin
        C := 2 + (Row * 60) + Col;
        GridX := 12 + Col;
        GridY := 4 + Row;

        if C > MaxClust + 1 then
        begin
          WriteCell(GridX, GridY, ' ', ATTR_DIALOG_BG);
        end
        else
        begin
          FatVal := FatGetEntry(C);
          IsSel := (SelFileClusters[C shr 3] and (1 shl (C and 7))) <> 0;
          HasP := (HasPred[C shr 3] and (1 shl (C and 7))) <> 0;

          if FatVal = 0 then
          begin
            Chr := #250; { Small dot }
            Attr := $17; { Light Gray on Blue }
          end
          else if FatVal = FAT12_ENTRY_BAD then
          begin
            Chr := 'B';
            Attr := $74; { Red on White }
          end
          else if IsSel then
          begin
            Attr := $4E; { Bright Yellow on Red }
            if FatVal >= FAT12_ENTRY_EOC_MIN then
              Chr := #17   { Filled < (End of Chain) }
            else if not HasP then
              Chr := #16   { Filled > (Start of Chain) }
            else
              Chr := '*';  { Selected file mid-chain }
          end
          else if FatVal >= FAT12_ENTRY_EOC_MIN then
          begin
            Chr := #17; { Filled < for End of Chain }
            Attr := $1B; { Light Cyan on Blue }
          end
          else if not HasP then
          begin
            Chr := #16; { Filled > for Start of Chain }
            Attr := $1E; { Bright Yellow on Blue }
          end
          else
          begin
            Chr := #254; { Square block for Mid-Chain }
            Attr := $1A; { Light Green on Blue }
          end;

          if C = CurClust then
            Attr := ATTR_MENU_ACT; { Inverse cursor }

          WriteCell(GridX, GridY, Chr, Attr);
        end;
      end;
    end;

    ByteOff := Layout.DataAreaStart + LongInt(CurClust - 2) * Layout.BytesPerCluster;
    PhysSec := ByteOff div 512;
    SecsPerCyl := Layout.Sides * Layout.SectorsPerTrack;
    if SecsPerCyl > 0 then
    begin
      Cyl := PhysSec div SecsPerCyl;
      Head := (PhysSec mod SecsPerCyl) div Layout.SectorsPerTrack;
      Sec := ((PhysSec mod SecsPerCyl) mod Layout.SectorsPerTrack) + 1;
    end
    else
    begin
      Cyl := 0; Head := 0; Sec := 0;
    end;

    FatVal := FatGetEntry(CurClust);
    HasP := (HasPred[CurClust shr 3] and (1 shl (CurClust and 7))) <> 0;
    if FatVal = 0 then
    begin
      StatusStr := 'FREE';
      NextStr := 'None';
    end
    else if FatVal = FAT12_ENTRY_BAD then
    begin
      StatusStr := 'BAD CLUSTER';
      NextStr := 'N/A';
    end
    else if FatVal >= FAT12_ENTRY_EOC_MIN then
    begin
      if not HasP then
        StatusStr := 'SINGLE CLUST'
      else
        StatusStr := 'END OF CHAIN';
      NextStr := 'EOF ($' + HexStrWord(FatVal) + ')';
    end
    else if not HasP then
    begin
      StatusStr := 'START OF CHAIN';
      NextStr := '#' + IntToStr(FatVal);
    end
    else
    begin
      StatusStr := 'MID-CHAIN';
      NextStr := '#' + IntToStr(FatVal);
    end;

    FindClusterOwner(CurClust, OwnerName, ChainPos, ChainLen, IsSelOwner);

    LineStr := '--- Cluster #' + IntToStr(CurClust) +
      ' -------------------------------------------------------------';
    WriteStr(3, 19, Copy(LineStr, 1, 74), ATTR_DIALOG_BD);

    LineStr := 'Physical: Sector ' + FormatNum(PhysSec) + ' (Cyl ' + IntToStr(Cyl) +
      ', Head ' + IntToStr(Head) + ', Sec ' + IntToStr(Sec) + ') | Offset: ' + FormatNum(ByteOff) + ' B';
    WriteStr(3, 20, PadRight(Copy(LineStr, 1, 74), 74), ATTR_DIALOG_BG);

    LineStr := 'Status:   ' + PadRight(StatusStr, 14) + ' | Next Clust: ' + PadRight(NextStr, 12);
    if OwnerName <> '' then
      LineStr := LineStr + ' | Owner: ' + OwnerName + ' (Clu ' + IntToStr(ChainPos) + '/' + IntToStr(ChainLen) + ')'
    else if FatVal = 0 then
      LineStr := LineStr + ' | Owner: [Free Space]'
    else
      LineStr := LineStr + ' | Owner: [Unlinked Data]';
    WriteStr(3, 21, PadRight(Copy(LineStr, 1, 74), 74), ATTR_DIALOG_HL);

    WriteStr(3, 22,
      'Legend:  ' + #250 + ' Free   ' + #16 + ' Start   ' + #254 + ' Mid   ' + #17 + ' End   * Sel. File   B Bad',
      ATTR_DIALOG_BG);
    WriteCell(12, 22, #250, $17);
    WriteCell(21, 22, #16,  $1E);
    WriteCell(31, 22, #254, $1A);
    WriteCell(39, 22, #17,  $1B);
    WriteCell(47, 22, '*',  $4E);
    WriteCell(62, 22, 'B',  $74);
    WriteStr(3, 23, '[Arrows] Select  [Enter] Hex  [Tab] Next  [B] Boot Sec  [Esc] Close ', ATTR_STATUS);
    MouseShow;

    Event := GetInputEvent(Ch, Scan, MX, MY, DblClick);

    if Event = EVENT_KEY then
    begin
      if (Ch = #27) or (UpCase(Ch) = 'Q') then Break;

      case Scan of
        KEY_LEFT:     if CurClust > 2 then Dec(CurClust);
        KEY_RIGHT:    if CurClust < MaxClust + 1 then Inc(CurClust);
        KEY_UP:       if CurClust >= 62 then Dec(CurClust, 60);
        KEY_DOWN:     if CurClust + 60 <= MaxClust + 1 then Inc(CurClust, 60);
        KEY_PAGEUP:   if CurClust >= 302 then Dec(CurClust, 300) else CurClust := 2;
        KEY_PAGEDOWN: if CurClust + 300 <= MaxClust + 1 then Inc(CurClust, 300) else CurClust := MaxClust + 1;
        KEY_HOME:     CurClust := 2;
        KEY_END:      CurClust := MaxClust + 1;
      end;

      if Ch = #9 then
      begin
        FatVal := FatGetEntry(CurClust);
        if (FatVal >= 2) and (FatVal < FAT12_ENTRY_EOC_MIN) then
          CurClust := FatVal;
      end;

      if UpCase(Ch) = 'B' then
      begin
        ShowBootSectorHexModal;
      end;

      if Ch = #13 then
      begin
        InteractiveFileViewer(True);
      end;
    end
    else if Event = EVENT_CLICK then
    begin
      if (MY >= 4) and (MY <= 18) and (MX >= 12) and (MX <= 71) then
      begin
        ClickedClust := 2 + (MY - 4) * 60 + (MX - 12);
        if (ClickedClust >= 2) and (ClickedClust <= MaxClust + 1) then
        begin
          CurClust := ClickedClust;
          if DblClick then
            InteractiveFileViewer(True);
        end;
      end
      else if (MY = 23) and (MX >= 41) and (MX <= 64) then
      begin
        ShowBootSectorHexModal;
      end
      else if (MY = 23) and (MX >= 65) then
      begin
        Break;
      end;
    end;
  until False;

  MouseHide;
  RestoreArea(1, 1, 78, 23, Saved);
  MouseShow;
end;

procedure WriteImageToFloppyModal;
var
  Saved: PPopupSave;
  DriveNum: Byte;
  DriveLetter: Char;
  Tracks, Sides, SPT: Word;
  TotalSec: Word;
  OrigTracks, OrigSides, OrigSPT, OrigTotalSec: Word;
  Cyl, Head: Word;
  CylTrackSecs: Word;
  Buffer: array[0..11 * 512 - 1] of Byte;
  ActualRead: Word;
  Status: Byte;
  Retry: Integer;
  Success: Boolean;
  SecWritten: Word;
  Percent: Integer;
  BarLen: Integer;
  BarStr: string[26];
  J: Integer;
  Ch: Char;
  Scan: Byte;
  MX, MY: Integer;
  DblClick: Boolean;
  Event: Integer;
  Aborted: Boolean;
  ErrStr: string[40];
  ImgOffset: LongInt;
  CanFit720: Boolean;
  Repack720: Boolean;
  UseRepackFile: Boolean;
  NeededClust, RootCount: Word;
  TotalFileBytes: LongInt;
  RepackFile: string[80];
  RepackErrMsg: string[80];
  RepackLineStr: string[70];
  RepackF: file;
  ActiveBtn: Integer;
begin
  ActiveBtn := 0;
  if (not ImageIsOpen) or (ActiveImagePath = '') then
  begin
    Saved := SaveArea(15, 8, 65, 16);
    MouseHide;
    FillBox(15, 8, 65, 16, ' ', ATTR_DIALOG_BG);
    DrawFrame(15, 8, 65, 16, ATTR_DIALOG_BD, 'Write Floppy');
    WriteStr(18, 11, 'No disk image is currently open!', ATTR_DIALOG_HL);
    WriteStr(18, 13, 'Press any key or click to return...', ATTR_DIALOG_BG);
    MouseShow;
    GetInputEvent(Ch, Scan, MX, MY, DblClick);
    MouseHide;
    RestoreArea(15, 8, 65, 16, Saved);
    MouseShow;
    Exit;
  end;

  DriveNum := 0; { Default Drive A: }
  OrigTracks := Layout.Tracks;
  OrigSides := Layout.Sides;
  OrigSPT := Layout.SectorsPerTrack;
  OrigTotalSec := Layout.TotalSectors;
  if OrigTracks = 0 then OrigTracks := 80;
  if OrigSides = 0 then OrigSides := 2;
  if OrigSPT = 0 then OrigSPT := 9;
  if OrigTotalSec = 0 then OrigTotalSec := OrigTracks * OrigSides * OrigSPT;

  Tracks := OrigTracks;
  Sides := OrigSides;
  SPT := OrigSPT;
  TotalSec := OrigTotalSec;

  Repack720 := False; { Default OFF }
  if AppDir <> '' then
    RepackFile := AppDir + 'ST_720.$$$'
  else
    RepackFile := 'ST_720.$$$';

  CanFit720 := CanRepackDiskTo720K(ActiveImageFile, Layout.DataAreaStart,
                 Layout.BytesPerCluster, Layout.RootDirStart,
                 Layout.RootDirSectors, BPB.SectorsPerCluster,
                 @FatBuf, NeededClust, RootCount, TotalFileBytes);

  Saved := SaveArea(6, 4, 73, 20);
  repeat
    MouseHide;
    FillBox(6, 4, 73, 20, ' ', ATTR_DIALOG_BG);
    DrawFrame(6, 4, 73, 20, ATTR_DIALOG_BD, ' Write Image to Physical Floppy Disk ');

    WriteStr(9, 6,  'Source Image:  ' + Copy(ActiveImagePath, 1, 40), ATTR_DIALOG_HL);

    if Repack720 then
    begin
      WriteStr(9, 7, PadRight('Write Format:  80 Tracks, 2 Sides, 9 Sectors/Track (720 KB)', 62), ATTR_DIALOG_BG);
      WriteStr(9, 8, PadRight('Total Sectors: 1440 (720 KB)', 62), ATTR_DIALOG_BG);
    end
    else
    begin
      WriteStr(9, 7, PadRight('Write Format:  ' + IntToStr(OrigTracks) + ' Tracks, ' +
        IntToStr(OrigSides) + ' Sides, ' + IntToStr(OrigSPT) + ' Sectors/Track', 62), ATTR_DIALOG_BG);
      WriteStr(9, 8, PadRight('Total Sectors: ' + IntToStr(OrigTotalSec) + ' (' +
        IntToStr(LongInt(OrigTotalSec) * 512 div 1024) + ' KB)', 62), ATTR_DIALOG_BG);
    end;

    if DriveNum = 0 then DriveLetter := 'A' else DriveLetter := 'B';

    WriteStr(9, 10, 'Target Drive:  [< Drive ' + DriveLetter +
      ': (3.5") >]  (A/B, Arrows, Click)', ATTR_DIALOG_HL);

    if CanFit720 then
    begin
      if Repack720 then
      begin
        RepackLineStr := 'Repack to 720K: [< YES >]  (80 Trk, 2 Sides, 9 Sec, R/Click)';
        WriteStr(9, 11, PadRight(RepackLineStr, 62), ATTR_DIALOG_OK);
      end
      else
      begin
        RepackLineStr := 'Repack to 720K: [< NO  >]  (Fits: ' +
          IntToStr(TotalFileBytes div 1024) + ' KB, press R/Click)';
        WriteStr(9, 11, PadRight(RepackLineStr, 62), ATTR_DIALOG_BG);
      end;
    end
    else
    begin
      RepackLineStr := 'Repack to 720K: [ N/A  ]  (Content ' +
        IntToStr(TotalFileBytes div 1024) + ' KB exceeds 720K limit)';
      WriteStr(9, 11, PadRight(RepackLineStr, 62), ATTR_DIALOG_HL);
    end;

    WriteStr(9, 12, 'WARNING: This will OVERWRITE ALL EXISTING DATA on Drive ' + DriveLetter + ':!', ATTR_NORMAL);
    WriteStr(9, 13, 'Please insert an initialized diskette (not write-protected).', ATTR_DIALOG_BG);

    if ActiveBtn = 0 then
    begin
      WriteStr(14, 16, '[  START WRITE (W/Enter)  ]', ATTR_MENU_SEL);
      WriteStr(44, 16, '[  CANCEL (Esc)  ]', ATTR_DIALOG_HL);
    end
    else
    begin
      WriteStr(14, 16, '[  START WRITE (W/Enter)  ]', ATTR_DIALOG_HL);
      WriteStr(44, 16, '[  CANCEL (Esc)  ]', ATTR_MENU_SEL);
    end;
    WriteStr(9, 18, 'Uses DOS / BIOS Int 13h raw track writing with error retries.', ATTR_STATUS);
    MouseShow;

    Event := GetInputEvent(Ch, Scan, MX, MY, DblClick);
    if Event = EVENT_KEY then
    begin
      if (Ch = #27) or (UpCase(Ch) = 'C') then
      begin
        MouseHide;
        RestoreArea(6, 4, 73, 20, Saved);
        MouseShow;
        Exit;
      end;
      if (Ch = #9) or (Scan = KEY_TAB) then
        ActiveBtn := 1 - ActiveBtn;
      if (UpCase(Ch) = 'A') then DriveNum := 0;
      if (UpCase(Ch) = 'B') then DriveNum := 1;
      if (Scan = KEY_LEFT) or (Scan = KEY_RIGHT) then
        DriveNum := 1 - DriveNum;
      if (UpCase(Ch) = 'R') then
      begin
        if CanFit720 then Repack720 := not Repack720;
      end;
      if (Ch = ' ') then
      begin
        if ActiveBtn = 1 then
        begin
          MouseHide;
          RestoreArea(6, 4, 73, 20, Saved);
          MouseShow;
          Exit;
        end
        else if CanFit720 then
          Repack720 := not Repack720;
      end;
      if (Ch = #13) then
      begin
        if ActiveBtn = 1 then
        begin
          MouseHide;
          RestoreArea(6, 4, 73, 20, Saved);
          MouseShow;
          Exit;
        end
        else Break;
      end;
      if (UpCase(Ch) = 'W') then begin ActiveBtn := 0; Break; end;
    end
    else if Event = EVENT_CLICK then
    begin
      if (MY = 10) and (MX >= 9) and (MX <= 65) then
        DriveNum := 1 - DriveNum
      else if (MY = 11) and (MX >= 9) and (MX <= 65) then
      begin
        if CanFit720 then
          Repack720 := not Repack720;
      end
      else if (MY = 16) and (MX >= 14) and (MX <= 38) then
      begin
        ActiveBtn := 0;
        Break;
      end
      else if (MY = 16) and (MX >= 44) and (MX <= 62) then
      begin
        ActiveBtn := 1;
        MouseHide;
        RestoreArea(6, 4, 73, 20, Saved);
        MouseShow;
        Exit;
      end
      else if (MY < 4) or (MY > 20) or (MX < 6) or (MX > 73) then
      begin
        MouseHide;
        RestoreArea(6, 4, 73, 20, Saved);
        MouseShow;
        Exit;
      end;
    end;
  until False;

  UseRepackFile := False;
  if Repack720 then
  begin
    MouseHide;
    FillBox(8, 7, 71, 18, ' ', ATTR_DIALOG_BG);
    DrawFrame(8, 7, 71, 18, ATTR_DIALOG_BD, ' Repacking to 720 KB Floppy Image ... ');
    WriteStr(11, 10, 'Repacking files into standard 720 KB geometry...', ATTR_DIALOG_HL);
    WriteStr(11, 12, 'Please wait...', ATTR_DIALOG_BG);
    MouseShow;

    if not RepackDiskTo720K(ActiveImageFile, Layout.DataAreaStart,
                            Layout.BytesPerCluster, Layout.RootDirStart,
                            Layout.RootDirSectors, BPB.SectorsPerCluster,
                            @FatBuf, RawBootSector, RepackFile, RepackErrMsg) then
    begin
      MouseHide;
      FillBox(8, 7, 71, 18, ' ', ATTR_DIALOG_BG);
      DrawFrame(8, 7, 71, 18, ATTR_DIALOG_BD, ' Repack Failed ');
      WriteStr(11, 10, 'Repack to 720 KB Failed!', ATTR_NORMAL);
      WriteStr(11, 12, 'Reason: ' + Copy(RepackErrMsg, 1, 45), ATTR_NORMAL);
      WriteStr(11, 15, 'Press any key or click to return...', ATTR_DIALOG_HL);
      MouseShow;
      GetInputEvent(Ch, Scan, MX, MY, DblClick);
      MouseHide;
      RestoreArea(6, 4, 73, 20, Saved);
      MouseShow;
      Exit;
    end;

    Assign(RepackF, RepackFile);
    {$I-}
    Reset(RepackF, 1);
    {$I+}
    if IOResult <> 0 then
    begin
      MouseHide;
      FillBox(8, 7, 71, 18, ' ', ATTR_DIALOG_BG);
      DrawFrame(8, 7, 71, 18, ATTR_DIALOG_BD, ' Error ');
      WriteStr(11, 10, 'Cannot open temporary 720 KB file!', ATTR_NORMAL);
      WriteStr(11, 15, 'Press any key or click to return...', ATTR_DIALOG_HL);
      MouseShow;
      GetInputEvent(Ch, Scan, MX, MY, DblClick);
      MouseHide;
      RestoreArea(6, 4, 73, 20, Saved);
      MouseShow;
      Exit;
    end;

    UseRepackFile := True;
    Tracks := 80;
    Sides := 2;
    SPT := 9;
    TotalSec := 1440;
  end
  else
  begin
    Tracks := OrigTracks;
    Sides := OrigSides;
    SPT := OrigSPT;
    TotalSec := OrigTotalSec;
  end;

  MouseHide;
  FillBox(8, 7, 71, 18, ' ', ATTR_DIALOG_BG);
  DrawFrame(8, 7, 71, 18, ATTR_DIALOG_BD, ' Writing to Drive ' + DriveLetter + ': ... ');

  WriteStr(11, 9,  'Resetting drive controller...', ATTR_DIALOG_HL);
  BiosDiskReset(DriveNum);

  CylTrackSecs := SPT;
  SecWritten := 0;
  Aborted := False;
  ImgOffset := 0;

  for Cyl := 0 to Tracks - 1 do
  begin
    for Head := 0 to Sides - 1 do
    begin
      WriteStr(11, 9,  'Writing Cylinder: ' + PadRight(IntToStr(Cyl) + '/' + IntToStr(Tracks - 1), 10) +
        ' Head: ' + IntToStr(Head) + '/' + IntToStr(Sides - 1) + '    ', ATTR_DIALOG_HL);

      if UseRepackFile then
      begin
        Seek(RepackF, ImgOffset);
        BlockRead(RepackF, Buffer, CylTrackSecs * 512, ActualRead);
      end
      else
      begin
        Seek(ActiveImageFile, ImgOffset);
        BlockRead(ActiveImageFile, Buffer, CylTrackSecs * 512, ActualRead);
      end;
      if ActualRead < CylTrackSecs * 512 then
        FillChar(Buffer[ActualRead], CylTrackSecs * 512 - ActualRead, 0);

      Success := False;
      for Retry := 1 to 3 do
      begin
        Status := BiosWriteSectors(DriveNum, Head, Cyl, 1, CylTrackSecs, Buffer);
        if Status = 0 then
        begin
          Success := True;
          Break;
        end;
        BiosDiskReset(DriveNum);
      end;

      if not Success then
      begin
        ErrStr := BiosDiskErrorStr(Status);
        WriteStr(11, 11, 'Disk Write Failed on Cyl ' + IntToStr(Cyl) + ' Head ' + IntToStr(Head) + '!', ATTR_NORMAL);
        WriteStr(11, 12, 'Reason: ' + ErrStr, ATTR_NORMAL);
        WriteStr(11, 14, 'Check diskette in Drive ' + DriveLetter + ': and write-protect notch.', ATTR_DIALOG_BG);
        WriteStr(11, 16, 'Press any key or click to return...', ATTR_DIALOG_HL);
        if UseRepackFile then
        begin
          {$I-}
          Close(RepackF);
          if IOResult <> 0 then ;
          Assign(RepackF, RepackFile);
          Erase(RepackF);
          if IOResult <> 0 then ;
          {$I+}
        end;
        MouseShow;
        GetInputEvent(Ch, Scan, MX, MY, DblClick);
        MouseHide;
        RestoreArea(6, 4, 73, 20, Saved);
        MouseShow;
        Exit;
      end;

      Inc(SecWritten, CylTrackSecs);
      Inc(ImgOffset, LongInt(CylTrackSecs) * 512);

      Percent := Integer((LongInt(SecWritten) * 100) div TotalSec);
      BarLen := (Percent * 20) div 100;
      BarStr := '[';
      for J := 1 to 20 do
        if J <= BarLen then BarStr := BarStr + #219 else BarStr := BarStr + #176;
      BarStr := BarStr + '] ' + IntToStr(Percent) + '%';
      WriteStr(11, 11, 'Progress: ' + BarStr + ' (' + IntToStr(SecWritten) +
        '/' + IntToStr(TotalSec) + ' sec)', ATTR_DIALOG_BG);

      if KeyWaiting then
      begin
        Ch := ReadKeyBIOS(Scan);
        if Ch = #27 then
        begin
          Aborted := True;
          Break;
        end;
      end;
    end;
    if Aborted then Break;
  end;

  if UseRepackFile then
  begin
    {$I-}
    Close(RepackF);
    if IOResult <> 0 then ;
    Assign(RepackF, RepackFile);
    Erase(RepackF);
    if IOResult <> 0 then ;
    {$I+}
  end;

  BiosDiskReset(DriveNum);

  if Aborted then
  begin
    WriteStr(11, 13, 'Operation aborted by user! Disk may be incomplete.', ATTR_NORMAL);
  end
  else
  begin
    WriteStr(11, 13, 'Write Complete! ' + IntToStr(SecWritten) + ' sectors written successfully.', ATTR_DIALOG_HL);
    WriteStr(11, 14, 'Floppy disk in Drive ' + DriveLetter + ': is ready for use on Atari ST.', ATTR_DIALOG_BG);
  end;
  WriteStr(11, 16, 'Press any key or click to return...', ATTR_DIALOG_HL);
  MouseShow;
  GetInputEvent(Ch, Scan, MX, MY, DblClick);
  MouseHide;
  RestoreArea(6, 4, 73, 20, Saved);
  MouseShow;
end;

procedure ReadFloppyToImageModal;
var
  OutName: TString80;
  Fit720, Opened: Boolean;
  Total, Bad, NeededClust, RootCount: Word;
  TotalFileBytes: LongInt;
  Msg: string[60];
  Tmp, ErrMsg: string[80];
begin
  if not FloppyReadDialog(OutName, Fit720, Total, Bad) then Exit;
  Opened := OpenImage(OutName);
  Msg := '';
  if Fit720 then
  begin
    if Total <= 1440 then
      Msg := 'Already 720 KB or smaller.'
    else if not Opened then
      Msg := 'Cannot repack: not a valid FAT12 disk.'
    else
    begin
      Tmp := AppDir + 'ST_RD.$$$';
      if not CanRepackDiskTo720K(ActiveImageFile, Layout.DataAreaStart, Layout.BytesPerCluster,
           Layout.RootDirStart, Layout.RootDirSectors, BPB.SectorsPerCluster, @FatBuf,
           NeededClust, RootCount, TotalFileBytes) then
        Msg := 'Does not fit 720K; kept full image.'
      else if not RepackDiskTo720K(ActiveImageFile, Layout.DataAreaStart, Layout.BytesPerCluster,
           Layout.RootDirStart, Layout.RootDirSectors, BPB.SectorsPerCluster, @FatBuf,
           RawBootSector, Tmp, ErrMsg) then
        Msg := 'Repack failed.'
      else
      begin
        CloseImage;
        if CopyFileTo(Tmp, OutName) then Msg := 'Repacked to 720 KB.' else Msg := 'Repack copy failed!';
        EraseFileQuiet(Tmp);
        Opened := OpenImage(OutName);
      end;
    end;
  end;
  FloppyReadResult(OutName, Bad, Msg, Opened);
  if Opened then ReadCurrentDirectory;
end;

procedure ShowBootSectorHexModal;
var
  Saved: PPopupSave;
  ScrollRow: Integer;
  R, C, Offset: Integer;
  HexLine: string;
  AscLine: string;
  B: Byte;
  Ch: Char;
  Scan: Byte;
  MX, MY: Integer;
  DblClick: Boolean;
  Event: Integer;
  VRes: TVirusResult;
  StatusMsg: string[72];
  BinF: file;
  ActualW: Word;
  IsExec, IsPC: Boolean;
  HeaderStr: string[74];
  LineAttr: Byte;
begin
  if (not ImageIsOpen) or (ActiveImagePath = '') then Exit;


  Saved := SaveArea(2, 1, 77, 23);
  MouseHide;
  FillBox(2, 1, 77, 23, ' ', ATTR_DIALOG_BG);
  DrawFrame(2, 1, 77, 23, ATTR_DIALOG_BD, ' Atari ST Boot Sector Inspector (Hex & BPB) ');

  ScrollRow := 0;
  StatusMsg := 'Press [D] Disinfect, [I] Immunize, [K] PC Boot, [S] Save BOOTSECT.BIN';

  repeat
    MouseHide;
    ScanBootSectorData(RawBootSector, VRes);
    IsExec := (VRes.BootSum = ATARI_BOOT_EXEC_SUM);
    IsPC := (RawBootSector[510] = $55) and (RawBootSector[511] = $AA);

    HeaderStr := 'Sum: $' + HexStrWord(VRes.BootSum);
    if IsExec then
      HeaderStr := HeaderStr + ' [Exec: YES]'
    else
      HeaderStr := HeaderStr + ' [Exec: NO]';

    if IsPC then
      HeaderStr := HeaderStr + '  PC Boot: [YES]'
    else
      HeaderStr := HeaderStr + '  PC Boot: [NO]';

    WriteStr(4, 2, HeaderStr, ATTR_DIALOG_BG);
    if VRes.ThreatFound then
      WriteStr(4 + Length(HeaderStr), 2,
        PadRight('  Virus: [' + VRes.Name + ']', 72 - Length(HeaderStr)), ATTR_DIALOG_ERR)
    else
      WriteStr(4 + Length(HeaderStr), 2,
        PadRight('  Status: [Clean]', 72 - Length(HeaderStr)), ATTR_DIALOG_OK);

    for R := 0 to 15 do
    begin
      Offset := (ScrollRow + R) * 16;
      HexLine := HexStrWord(Offset) + ': ';
      AscLine := '';

      for C := 0 to 15 do
      begin
        B := RawBootSector[Offset + C];
        if C = 8 then HexLine := HexLine + '-'
        else if C > 0 then HexLine := HexLine + ' ';
        HexLine := HexLine + HexStrByte(B);

        if (B >= 32) and (B <= 126) then
          AscLine := AscLine + Chr(B)
        else
          AscLine := AscLine + '.';
      end;

      if (ScrollRow + R = 0) then
        LineAttr := ATTR_DIALOG_HL
      else if (ScrollRow + R = 31) then
        LineAttr := ATTR_DIALOG_HL
      else
        LineAttr := ATTR_DIALOG_BG;

      WriteStr(4, 4 + R, HexLine + '  ' + AscLine, LineAttr);
    end;

    WriteStr(4, 20, '$00: Branch  $02: OEM  $0B..$1D: BPB  $1E: Code  $1FE: Atari/PC Sum', ATTR_DIALOG_BD);
    WriteStr(4, 21, PadRight(StatusMsg, 70), ATTR_DIALOG_HL);
    WriteStr(4, 22, '[Arrows] Scroll  [D] Disinf  [I] Immun  [K] PC-Boot  [S] Save  [Esc] Exit', ATTR_STATUS);
    MouseShow;

    Event := GetInputEvent(Ch, Scan, MX, MY, DblClick);

    if Event = EVENT_KEY then
    begin
      if (Ch = #27) or (UpCase(Ch) = 'Q') then Break;

      case Scan of
        KEY_UP:       if ScrollRow > 0 then Dec(ScrollRow);
        KEY_DOWN:     if ScrollRow < 16 then Inc(ScrollRow);
        KEY_PAGEUP:   if ScrollRow >= 8 then Dec(ScrollRow, 8) else ScrollRow := 0;
        KEY_PAGEDOWN: if ScrollRow <= 8 then Inc(ScrollRow, 8) else ScrollRow := 16;
        KEY_HOME:     ScrollRow := 0;
        KEY_END:      ScrollRow := 16;
      end;

      case UpCase(Ch) of
        'D':
          begin
            if ImageIsReadOnly then
              StatusMsg := 'Cannot disinfect: Image is read-only!'
            else
            begin
              DisinfectBootData(RawBootSector);
              Seek(ActiveImageFile, 0);
              BlockWrite(ActiveImageFile, RawBootSector, 512, ActualW);
              LoadBootAndBPB;
              StatusMsg := 'Boot sector disinfected! Executable virus code removed.';
            end;
          end;
        'I':
          begin
            if ImageIsReadOnly then
              StatusMsg := 'Cannot immunize: Image is read-only!'
            else
            begin
              ImmunizeBootData(RawBootSector);
              Seek(ActiveImageFile, 0);
              BlockWrite(ActiveImageFile, RawBootSector, 512, ActualW);
              LoadBootAndBPB;
              StatusMsg := 'Boot sector immunized! Resident boot guard installed ($1234).';
            end;
          end;
        'K':
          begin
            if ImageIsReadOnly then
              StatusMsg := 'Cannot patch: Image is read-only!'
            else
            begin
              MakePCBootData(RawBootSector);
              Seek(ActiveImageFile, 0);
              BlockWrite(ActiveImageFile, RawBootSector, 512, ActualW);
              LoadBootAndBPB;
              StatusMsg := 'Boot sector patched for MS-DOS PC compatibility ($55AA).';
            end;
          end;
        'S':
          begin
            Assign(BinF, 'BOOTSECT.BIN');
            Rewrite(BinF, 1);
            if IOResult = 0 then
            begin
              BlockWrite(BinF, RawBootSector, 512, ActualW);
              Close(BinF);
              StatusMsg := 'Saved 512-byte raw boot sector to BOOTSECT.BIN in DOS.';
            end
            else
              StatusMsg := 'Error writing BOOTSECT.BIN to DOS!';
          end;
        'P', #9:
          begin
            ShowBPBModal;
            FillBox(2, 1, 77, 23, ' ', ATTR_DIALOG_BG);
            DrawFrame(2, 1, 77, 23, ATTR_DIALOG_BD, ' Atari ST Boot Sector Inspector (Hex & BPB) ');
          end;
      end;
    end
    else if Event = EVENT_CLICK then
    begin
      if (MY = 22) and (MX >= 70) then Break;
    end;
  until False;

  MouseHide;
  RestoreArea(2, 1, 77, 23, Saved);
  MouseShow;
end;

procedure ShowVirusScannerModal;
var
  Saved: PPopupSave;
  Ch: Char;
  Scan: Byte;
  MX, MY: Integer;
  DblClick: Boolean;
  Event: Integer;
  VRes, FileRes: TVirusResult;
  ActualW: Word;
  I: Integer;
  ScanBuf: array[0..2047] of Byte;
  ReadBytes: Word;
  ScannedFiles, InfectedFiles: Integer;
  StatusLine: string[70];
  StatusAttr: Byte;
  Pct, BarLen: Integer;
  BarStr: string[30];
  J: Integer;
begin
  if (not ImageIsOpen) or (ActiveImagePath = '') then Exit;

  Saved := SaveArea(4, 2, 75, 23);
  MouseHide;
  FillBox(4, 2, 75, 23, ' ', ATTR_DIALOG_BG);
  DrawFrame(4, 2, 75, 23, ATTR_DIALOG_BD, ' Atari ST Virus Scanner & Disinfector ');

  StatusLine := 'Press [F] to scan all executable files, or [D] to disinfect.';
  StatusAttr := ATTR_DIALOG_BG;

  repeat
    MouseHide;
    ScanBootSectorData(RawBootSector, VRes);

    WriteStr(6, 4, 'Disk Image: ' + Copy(ActiveImagePath, 1, 46), ATTR_DIALOG_HL);
    WriteStr(6, 5, '------------------------------------------------------------------', ATTR_DIALOG_BD);

    WriteStr(6, 6, '1. Boot Sector Status:', ATTR_DIALOG_HL);
    if VRes.ThreatFound then
    begin
      WriteStr(8, 7, '>>> THREAT DETECTED: ' + VRes.Name + ' <<<', ATTR_DIALOG_ERR);
      WriteStr(8, 8, 'Description: ' + Copy(VRes.Description, 1, 52), ATTR_DIALOG_BG);
      WriteStr(8, 9, 'Checksum:    $' + HexStrWord(VRes.BootSum) + '  (Atari Executable Boot: YES)', ATTR_DIALOG_BG);
      WriteStr(8, 10, 'Action:      [D] Disinfect Boot Sector   [I] Immunize Disk', ATTR_DIALOG_HL);
    end
    else
    begin
      WriteStr(8, 7, '[OK] Boot Sector is CLEAN. No known boot viruses detected.', ATTR_DIALOG_OK);
      if BPB.IsExecBoot then
        WriteStr(8, 8, 'Executable Boot: YES (Sum: $1234 - Valid Custom Boot / Loader)', ATTR_DIALOG_BG)
      else
        WriteStr(8, 8, 'Executable Boot: NO  (Standard Data / Non-Executable Disk)', ATTR_DIALOG_BG);
      WriteStr(8, 9, 'Signatures:  30 Atari ST Boot Viruses (Ghost, MAD, Signum, etc.)', ATTR_DIALOG_BG);
      WriteStr(8, 10, 'Action:      [I] Immunize Disk (Install resident anti-virus guard)', ATTR_DIALOG_HL);
    end;

    WriteStr(6, 12, '2. Executable Files Scanner (PRG / TOS / APP / ACC):', ATTR_DIALOG_HL);
    WriteStr(8, 13, 'File Signatures: Signum, Ghost Linkvirus, MAD, C''est La Vie...', ATTR_DIALOG_BG);
    WriteStr(8, 14, PadRight(StatusLine, 60), StatusAttr);

    WriteStr(6, 17, '------------------------------------------------------------------', ATTR_DIALOG_BD);
    WriteStr(6, 18, 'Options:  [F] Scan All Files  [D] Disinfect  [I] Immunize  [B] Hex', ATTR_DIALOG_BG);
    WriteStr(6, 21, '[F] Scan Files   [D] Disinfect   [I] Immunize   [B] Hex   [Esc] Close', ATTR_STATUS);
    MouseShow;

    Event := GetInputEvent(Ch, Scan, MX, MY, DblClick);

    if Event = EVENT_KEY then
    begin
      if (Ch = #27) or (UpCase(Ch) = 'Q') then Break;

      case UpCase(Ch) of
        'D':
          begin
            if ImageIsReadOnly then
            begin
              StatusLine := 'Cannot disinfect: Image is read-only!';
              StatusAttr := ATTR_DIALOG_ERR;
            end
            else
            begin
              DisinfectBootData(RawBootSector);
              Seek(ActiveImageFile, 0);
              BlockWrite(ActiveImageFile, RawBootSector, 512, ActualW);
              LoadBootAndBPB;
              StatusLine := 'Boot sector disinfected! Executable virus payload cleared.';
              StatusAttr := ATTR_DIALOG_OK;
            end;
          end;
        'I':
          begin
            if ImageIsReadOnly then
            begin
              StatusLine := 'Cannot immunize: Image is read-only!';
              StatusAttr := ATTR_DIALOG_ERR;
            end
            else
            begin
              ImmunizeBootData(RawBootSector);
              Seek(ActiveImageFile, 0);
              BlockWrite(ActiveImageFile, RawBootSector, 512, ActualW);
              LoadBootAndBPB;
              StatusLine := 'Boot sector immunized! Resident boot guard installed.';
              StatusAttr := ATTR_DIALOG_OK;
            end;
          end;
        'B':
          begin
            ShowBootSectorHexModal;
            FillBox(4, 2, 75, 23, ' ', ATTR_DIALOG_BG);
            DrawFrame(4, 2, 75, 23, ATTR_DIALOG_BD, ' Atari ST Virus Scanner & Disinfector ');
          end;
        'F':
          begin
            MouseHide;
            ScannedFiles := 0;
            InfectedFiles := 0;

            for I := 1 to ItemCount do
            begin
              if (not Items[I].IsDir) and (Items[I].StartCluster >= 2) then
              begin
                Pct := (I * 100) div ItemCount;
                BarLen := (Pct * 20) div 100;
                BarStr := '[';
                for J := 1 to 20 do
                  if J <= BarLen then BarStr := BarStr + #219 else BarStr := BarStr + #176;
                BarStr := BarStr + '] ' + IntToStr(Pct) + '%';
                WriteStr(8, 15, 'Scanning: ' + PadRight(Items[I].CleanName, 14) + ' ' + BarStr, ATTR_DIALOG_HL);

                ReadBytes := ReadFileBytes(Items[I].StartCluster, Items[I].Size, 0, ScanBuf, 2048);
                if ReadBytes > 0 then
                begin
                  if ScanFileMem(@ScanBuf, ReadBytes, Items[I].CleanName, FileRes) then
                  begin
                    Inc(InfectedFiles);
                    WriteStr(8, 16, 'Found: ' + Items[I].CleanName + ' -> ' + FileRes.Name, ATTR_DIALOG_ERR);
                  end;
                  Inc(ScannedFiles);
                end;
              end;
            end;

            if InfectedFiles = 0 then
            begin
              StatusLine := 'Scan Complete: ' + IntToStr(ScannedFiles) + ' files scanned, all CLEAN!';
              StatusAttr := ATTR_DIALOG_OK;
              WriteStr(8, 16, PadRight('', 55), ATTR_DIALOG_BG);
            end
            else
            begin
              StatusLine := 'Scan Complete: ' + IntToStr(InfectedFiles) + ' INFECTION(S) DETECTED!';
              StatusAttr := ATTR_DIALOG_ERR;
            end;
            WriteStr(8, 15, PadRight('', 55), ATTR_DIALOG_BG);
            MouseShow;
          end;
      end;
    end
    else if Event = EVENT_CLICK then
    begin
      if (MY = 21) and (MX >= 65) then Break;
    end;
  until False;

  MouseHide;
  RestoreArea(4, 2, 75, 23, Saved);
  MouseShow;
end;

procedure ShowSearchModal;
var
  Saved: PPopupSave;
  Pattern: TString80;
  SearchResults: PSearchArray;
  FoundCount: Integer;
  SelIdx, TopSIdx: Integer;
  Ch: Char;
  Scan: Byte;
  MX, MY: Integer;
  DblClick: Boolean;
  InEvent: Integer;
  Row, RIdx: Integer;
  LineStr, DispDir: string;
  Attr: Byte;
  I: Integer;
  TargetName: string[12];
  TargetParent: Word;
  TargetDir: string[36];
begin
  if (not ImageIsOpen) then Exit;

  { 1. Prompt for wildcard pattern }
  Saved := SaveArea(18, 9, 62, 15);
  MouseHide;
  FillBox(18, 9, 62, 15, ' ', ATTR_DIALOG_BG);
  DrawFrame(18, 9, 62, 15, ATTR_DIALOG_BD, 'Find Files on Disk');
  WriteStr(21, 11, 'Enter Wildcard (e.g. *.PRG):', ATTR_DIALOG_BG);
  Pattern := '*.PRG';
  PromptInput(21, 12, Pattern, 20);
  MouseShow;
  RestoreArea(18, 9, 62, 15, Saved);
  if Pattern = '' then Exit;

  { 2. Search recursively on heap buffer }
  New(SearchResults);
  FoundCount := SearchDiskRecursive(ActiveImageFile, Layout.DataAreaStart,
    Layout.BytesPerCluster, Layout.RootDirStart, Layout.RootDirSectors,
    BPB.SectorsPerCluster, @FatBuf, Pattern, SearchResults^, MAX_SEARCH_RESULTS);

  if FoundCount = 0 then
  begin
    Dispose(SearchResults);
    Saved := SaveArea(18, 9, 62, 15);
    MouseHide;
    FillBox(18, 9, 62, 15, ' ', ATTR_DIALOG_BG);
    DrawFrame(18, 9, 62, 15, ATTR_DIALOG_BD, 'Find Files on Disk');
    WriteStr(21, 11, 'No files matching pattern found!', ATTR_DIALOG_HL);
    WriteStr(21, 13, 'Press any key to return...', ATTR_STATUS);
    MouseShow;
    ReadKeyBIOS(Scan);
    RestoreArea(18, 9, 62, 15, Saved);
    Exit;
  end;

  { 3. Display interactive results viewer }
  Saved := SaveArea(4, 2, 76, 22);
  SelIdx := 0;
  TopSIdx := 0;

  repeat
    MouseHide;
    FillBox(4, 2, 76, 22, ' ', ATTR_DIALOG_BG);
    DrawFrame(4, 2, 76, 22, ATTR_DIALOG_BD, 'Search Results: ' + Copy(Pattern, 1, 16) +
      ' (' + IntToStr(FoundCount) + ' found)');

    WriteStr(6, 4, 'Folder             Name         Size   Attr  Date       Time', ATTR_HEADER);
    WriteCell(4, 4, #195, ATTR_DIALOG_BD);
    for I := 5 to 75 do WriteCell(I, 4, #196, ATTR_DIALOG_BD);
    WriteCell(76, 4, #180, ATTR_DIALOG_BD);

    for Row := 0 to 14 do
    begin
      RIdx := TopSIdx + Row;
      if RIdx < FoundCount then
      begin
        if RIdx = SelIdx then
          Attr := ATTR_DIALOG_SEL
        else if SearchResults^[RIdx].IsDir then
          Attr := ATTR_DIR
        else
          Attr := ATTR_DIALOG_BG;

        DispDir := Copy(SearchResults^[RIdx].DirPath, 1, 18);
        LineStr := ' ' + PadRight(DispDir, 18) + ' ' +
                   PadRight(SearchResults^[RIdx].Name, 12) + ' ' +
                   PadLeft(FormatFileSize(SearchResults^[RIdx].Size), 8) + ' ' +
                   FormatAttr(SearchResults^[RIdx].Attr) + ' ' +
                   TwoDigits(SearchResults^[RIdx].Month) + '-' +
                   TwoDigits(SearchResults^[RIdx].Day) + '-' +
                   IntToStr(SearchResults^[RIdx].Year) + ' ' +
                   TwoDigits(SearchResults^[RIdx].Hour) + ':' +
                   TwoDigits(SearchResults^[RIdx].Min);

        WriteStr(5, 5 + Row, PadRight(LineStr, 70), Attr);
      end
      else
        WriteStr(5, 5 + Row, PadRight('', 70), ATTR_DIALOG_BG);
    end;

    WriteStr(6, 21, '[Arrows] Select   [Enter] Go to Folder   [V] View   [Esc] Close', ATTR_STATUS);
    MouseShow;

    InEvent := GetInputEvent(Ch, Scan, MX, MY, DblClick);

    if InEvent = EVENT_KEY then
    begin
      if (Ch = #27) or (UpCase(Ch) = 'Q') then Break;

      case Scan of
        KEY_UP:
          begin
            if SelIdx > 0 then
            begin
              Dec(SelIdx);
              if SelIdx < TopSIdx then TopSIdx := SelIdx;
            end;
          end;
        KEY_DOWN:
          begin
            if SelIdx < FoundCount - 1 then
            begin
              Inc(SelIdx);
              if SelIdx >= TopSIdx + 15 then TopSIdx := SelIdx - 14;
            end;
          end;
        KEY_PAGEUP:
          begin
            SelIdx := SelIdx - 15;
            if SelIdx < 0 then SelIdx := 0;
            TopSIdx := TopSIdx - 15;
            if TopSIdx < 0 then TopSIdx := 0;
          end;
        KEY_PAGEDOWN:
          begin
            SelIdx := SelIdx + 15;
            if SelIdx >= FoundCount then SelIdx := FoundCount - 1;
            TopSIdx := TopSIdx + 15;
            if TopSIdx > FoundCount - 15 then TopSIdx := FoundCount - 15;
            if TopSIdx < 0 then TopSIdx := 0;
          end;
        KEY_HOME:
          begin SelIdx := 0; TopSIdx := 0; end;
        KEY_END:
          begin
            SelIdx := FoundCount - 1;
            TopSIdx := FoundCount - 15;
            if TopSIdx < 0 then TopSIdx := 0;
          end;
      end;

      if (Ch = #13) or (UpCase(Ch) = 'V') then
      begin
        TargetParent := SearchResults^[SelIdx].ParentCluster;
        TargetDir := SearchResults^[SelIdx].DirPath;
        TargetName := SearchResults^[SelIdx].Name;

        CurrentDirCluster := TargetParent;
        CurrentPath := TargetDir;
        ReadCurrentDirectory;

        for I := 1 to ItemCount do
          if Items[I].CleanName = TargetName then
          begin
            SelectedIdx := I;
            if SelectedIdx >= TopIdx + 19 then TopIdx := SelectedIdx - 18;
            Break;
          end;

        RestoreArea(4, 2, 76, 22, Saved);
        Dispose(SearchResults);

        if UpCase(Ch) = 'V' then
          InteractiveFileViewer(True);
        Exit;
      end;
    end;
  until False;

  RestoreArea(4, 2, 76, 22, Saved);
  Dispose(SearchResults);
end;

procedure ShowCatalogModal;
var
  Saved: PPopupSave;
  Ch: Char;
  Scan: Byte;
  DidExport: Boolean;
begin
  if (not ImageIsOpen) then Exit;

  Saved := SaveArea(14, 7, 66, 17);
  MouseHide;
  FillBox(14, 7, 66, 17, ' ', ATTR_DIALOG_BG);
  DrawFrame(14, 7, 66, 17, ATTR_DIALOG_BD, 'Export Disk Catalog');

  WriteStr(17, 9,  'Export All Disk Files & Folders:', ATTR_DIALOG_BG);
  WriteStr(17, 11, '[1] Text File (CATALOG.TXT)', ATTR_DIALOG_HL);
  WriteStr(17, 12, '[2] CSV Spreadsheet (CATALOG.CSV)', ATTR_DIALOG_HL);
  WriteStr(17, 13, '[3] Both Formats (TXT & CSV)', ATTR_DIALOG_HL);
  WriteStr(17, 15, 'Select [1], [2], or [3] (or Esc): ', ATTR_STATUS);
  MouseShow;

  repeat
    Ch := ReadKeyBIOS(Scan);
    if Scan = KEY_F10 then Ch := #27;
    if Ch = #27 then
    begin
      RestoreArea(14, 7, 66, 17, Saved);
      Exit;
    end;
  until Ch in ['1', '2', '3'];

  MouseHide;
  DidExport := False;
  if (Ch = '1') or (Ch = '3') then
    DidExport := ExportCatalogFile(ActiveImageFile, Layout.DataAreaStart,
      Layout.BytesPerCluster, Layout.RootDirStart, Layout.RootDirSectors,
      BPB.SectorsPerCluster, Layout.TotalClusters, Layout.FreeClusters,
      Layout.Tracks, BPB.Sides, BPB.SectorsPerTrack, Layout.TotalBytes,
      Layout.FreeBytes, @FatBuf, ActiveImagePath, 'CATALOG.TXT', False);

  if (Ch = '2') or (Ch = '3') then
    DidExport := ExportCatalogFile(ActiveImageFile, Layout.DataAreaStart,
      Layout.BytesPerCluster, Layout.RootDirStart, Layout.RootDirSectors,
      BPB.SectorsPerCluster, Layout.TotalClusters, Layout.FreeClusters,
      Layout.Tracks, BPB.Sides, BPB.SectorsPerTrack, Layout.TotalBytes,
      Layout.FreeBytes, @FatBuf, ActiveImagePath, 'CATALOG.CSV', True);

  if DidExport then
    WriteStr(17, 15, 'Catalog exported successfully! Any key.', ATTR_DIALOG_HL)
  else
    WriteStr(17, 15, 'Error exporting catalog file! Any key. ', ATTR_DIALOG_HL);

  MouseShow;
  ReadKeyBIOS(Scan);
  RestoreArea(14, 7, 66, 17, Saved);
end;

procedure ShowImportFileModal;
var
  Saved: PPopupSave;
  DosPath, TargetName: TString80;
  Name8, Ext3: string[8];
  ErrMsg: string;
  F: file;
  FileSizeVal: LongInt;
  Scan: Byte;
  I: Integer;
begin
  if (not ImageIsOpen) then Exit;
  if ImageIsReadOnly then
  begin
    Saved := SaveArea(14, 9, 66, 15);
    MouseHide;
    FillBox(14, 9, 66, 15, ' ', ATTR_DIALOG_BG);
    DrawFrame(14, 9, 66, 15, ATTR_DIALOG_BD, 'Import File');
    WriteStr(17, 11, 'Cannot import: Image is read-only!', ATTR_DIALOG_HL);
    WriteStr(17, 13, 'Press any key to return...', ATTR_STATUS);
    MouseShow;
    ReadKeyBIOS(Scan);
    RestoreArea(14, 9, 66, 15, Saved);
    Exit;
  end;

  Saved := SaveArea(10, 5, 70, 19);
  MouseHide;
  FillBox(10, 5, 70, 19, ' ', ATTR_DIALOG_BG);
  DrawFrame(10, 5, 70, 19, ATTR_DIALOG_BD, 'Import Host File to Disk Image');

  WriteStr(13, 7, 'Target Folder: ' + Copy(CurrentPath, 1, 35), ATTR_DIALOG_HL);
  WriteStr(13, 9, 'Enter Host DOS file path to import:', ATTR_DIALOG_BG);
  DosPath := '';
  PromptInput(13, 10, DosPath, 45);

  if DosPath = '' then
  begin
    RestoreArea(10, 5, 70, 19, Saved);
    Exit;
  end;

  Assign(F, DosPath);
  Reset(F, 1);
  if IOResult <> 0 then
  begin
    WriteStr(13, 12, 'Error: Host file not found! Press any key.   ', ATTR_DIALOG_HL);
    MouseShow;
    ReadKeyBIOS(Scan);
    RestoreArea(10, 5, 70, 19, Saved);
    Exit;
  end;
  FileSizeVal := FileSize(F);
  Close(F);

  if FileSizeVal > Layout.FreeBytes then
  begin
    WriteStr(13, 12, 'Error: Not enough free space on disk image!  ', ATTR_DIALOG_HL);
    MouseShow;
    ReadKeyBIOS(Scan);
    RestoreArea(10, 5, 70, 19, Saved);
    Exit;
  end;

  TargetName := '';
  for I := Length(DosPath) downto 1 do
    if (DosPath[I] = '\') or (DosPath[I] = '/') or (DosPath[I] = ':') then
    begin
      TargetName := Copy(DosPath, I + 1, Length(DosPath) - I);
      Break;
    end;
  if TargetName = '' then TargetName := DosPath;

  SanitizeTo83(TargetName, Name8, Ext3);
  TargetName := Name8;
  if Ext3 <> '' then TargetName := TargetName + '.' + Ext3;

  WriteStr(13, 12, 'Atari 8.3 Filename: ', ATTR_DIALOG_BG);
  PromptInput(34, 12, TargetName, 12);
  if TargetName = '' then
  begin
    RestoreArea(10, 5, 70, 19, Saved);
    Exit;
  end;

  WriteStr(13, 15, 'Injecting file into disk image...', ATTR_DIALOG_HL);

  if not ImportDosFile(ActiveImageFile, Layout.DataAreaStart, Layout.BytesPerCluster,
                       Layout.RootDirStart, Layout.RootDirSectors, BPB.SectorsPerCluster,
                       Layout.TotalClusters, @FatBuf, CurrentDirCluster,
                       DosPath, TargetName, ErrMsg) then
  begin
    WriteStr(13, 15, PadRight('Error: ' + Copy(ErrMsg, 1, 35) + '! Any key.', 52), ATTR_DIALOG_HL);
    MouseShow;
    ReadKeyBIOS(Scan);
  end
  else
  begin
    FlushFAT;
    CalculateFreeSpace;
    LoadBootAndBPB;
    ReadCurrentDirectory;
    WriteStr(13, 15, PadRight('Imported ' + TargetName + ' successfully! Any key.', 52), ATTR_DIALOG_HL);
    MouseShow;
    ReadKeyBIOS(Scan);
  end;

  RestoreArea(10, 5, 70, 19, Saved);
end;

procedure ShowRenameModal;
var
  Saved: PPopupSave;
  NewName: TString80;
  Name8, Ext3: string[8];
  FormattedName: string[12];
  Scan: Byte;
  I: Integer;
begin
  if (not ImageIsOpen) or (ItemCount = 0) or (SelectedIdx < 1) or (SelectedIdx > ItemCount) then Exit;
  if Items[SelectedIdx].DisplayName = '..' then Exit;
  if ImageIsReadOnly then
  begin
    Saved := SaveArea(14, 9, 66, 15);
    MouseHide;
    FillBox(14, 9, 66, 15, ' ', ATTR_DIALOG_BG);
    DrawFrame(14, 9, 66, 15, ATTR_DIALOG_BD, 'Rename Item');
    WriteStr(17, 11, 'Cannot rename: Image is read-only!', ATTR_DIALOG_HL);
    WriteStr(17, 13, 'Press any key to return...', ATTR_STATUS);
    MouseShow;
    ReadKeyBIOS(Scan);
    RestoreArea(14, 9, 66, 15, Saved);
    Exit;
  end;

  Saved := SaveArea(14, 7, 66, 17);
  MouseHide;
  FillBox(14, 7, 66, 17, ' ', ATTR_DIALOG_BG);
  DrawFrame(14, 7, 66, 17, ATTR_DIALOG_BD, 'Rename File or Folder');

  WriteStr(17, 9,  'Current Name: ' + Items[SelectedIdx].CleanName, ATTR_DIALOG_BG);
  WriteStr(17, 11, 'Enter new 8.3 filename:', ATTR_DIALOG_BG);
  NewName := Items[SelectedIdx].CleanName;
  PromptInput(17, 12, NewName, 12);

  if (NewName = '') or (NewName = Items[SelectedIdx].CleanName) then
  begin
    RestoreArea(14, 7, 66, 17, Saved);
    Exit;
  end;

  SanitizeTo83(NewName, Name8, Ext3);
  FormattedName := Name8;
  if Ext3 <> '' then FormattedName := FormattedName + '.' + Ext3;

  for I := 1 to ItemCount do
  begin
    if (I <> SelectedIdx) and (Items[I].CleanName = FormattedName) then
    begin
      WriteStr(17, 14, 'Error: Name already exists! Any key.', ATTR_DIALOG_HL);
      MouseShow;
      ReadKeyBIOS(Scan);
      RestoreArea(14, 7, 66, 17, Saved);
      Exit;
    end;
  end;

  if RenameDirEntry(ActiveImageFile, Items[SelectedIdx].EntryOffset, Name8, Ext3) then
  begin
    ReadCurrentDirectory;
    WriteStr(17, 14, 'Renamed successfully! Any key.      ', ATTR_DIALOG_HL);
  end
  else
    WriteStr(17, 14, 'Error renaming entry! Any key.      ', ATTR_DIALOG_HL);

  MouseShow;
  ReadKeyBIOS(Scan);
  RestoreArea(14, 7, 66, 17, Saved);
end;

procedure ShowAttrModal;
var
  Saved: PPopupSave;
  CurAttr, OrigAttr: Byte;
  Ch: Char;
  Scan: Byte;
  function OnOff(B: Boolean): string;
  begin
    if B then OnOff := '[ON] ' else OnOff := '[OFF]';
  end;
begin
  if (not ImageIsOpen) or (ItemCount = 0) or (SelectedIdx < 1) or (SelectedIdx > ItemCount) then Exit;
  if Items[SelectedIdx].DisplayName = '..' then Exit;
  if ImageIsReadOnly then
  begin
    Saved := SaveArea(14, 9, 66, 15);
    MouseHide;
    FillBox(14, 9, 66, 15, ' ', ATTR_DIALOG_BG);
    DrawFrame(14, 9, 66, 15, ATTR_DIALOG_BD, 'File Attributes');
    WriteStr(17, 11, 'Cannot edit: Image is read-only!', ATTR_DIALOG_HL);
    WriteStr(17, 13, 'Press any key to return...', ATTR_STATUS);
    MouseShow;
    ReadKeyBIOS(Scan);
    RestoreArea(14, 9, 66, 15, Saved);
    Exit;
  end;

  CurAttr := Items[SelectedIdx].Attr;
  OrigAttr := CurAttr;
  Saved := SaveArea(14, 6, 66, 18);

  repeat
    MouseHide;
    FillBox(14, 6, 66, 18, ' ', ATTR_DIALOG_BG);
    DrawFrame(14, 6, 66, 18, ATTR_DIALOG_BD, 'Edit File Attributes');

    WriteStr(17, 8,  'Item: ' + Items[SelectedIdx].CleanName, ATTR_DIALOG_BG);
    WriteStr(17, 10, '[R] Read-Only : ' + OnOff((CurAttr and $01) <> 0), ATTR_DIALOG_HL);
    WriteStr(17, 11, '[H] Hidden    : ' + OnOff((CurAttr and $02) <> 0), ATTR_DIALOG_HL);
    WriteStr(17, 12, '[S] System    : ' + OnOff((CurAttr and $04) <> 0), ATTR_DIALOG_HL);
    WriteStr(17, 13, '[A] Archive   : ' + OnOff((CurAttr and $20) <> 0), ATTR_DIALOG_HL);
    WriteStr(17, 15, '[Enter] Save   [Esc] Cancel', ATTR_STATUS);
    MouseShow;

    Ch := ReadKeyBIOS(Scan);
    if Scan = KEY_F10 then Ch := #27;
    if Ch = #27 then Break;

    case UpCase(Ch) of
      'R': CurAttr := CurAttr xor $01;
      'H': CurAttr := CurAttr xor $02;
      'S': CurAttr := CurAttr xor $04;
      'A': CurAttr := CurAttr xor $20;
      #13:
        begin
          if CurAttr <> OrigAttr then
          begin
            if UpdateDirEntryAttr(ActiveImageFile, Items[SelectedIdx].EntryOffset, CurAttr) then
              ReadCurrentDirectory;
          end;
          Break;
        end;
    end;
  until False;

  RestoreArea(14, 6, 66, 18, Saved);
end;

procedure ShowMkdirModal;
var
  Saved: PPopupSave;
  FolderName: TString80;
  Name8, Ext3: string[8];
  ErrMsg: string;
  Scan: Byte;
  I: Integer;
begin
  if (not ImageIsOpen) then Exit;
  if ImageIsReadOnly then
  begin
    Saved := SaveArea(14, 9, 66, 15);
    MouseHide;
    FillBox(14, 9, 66, 15, ' ', ATTR_DIALOG_BG);
    DrawFrame(14, 9, 66, 15, ATTR_DIALOG_BD, 'Create Subfolder');
    WriteStr(17, 11, 'Cannot create: Image is read-only!', ATTR_DIALOG_HL);
    WriteStr(17, 13, 'Press any key to return...', ATTR_STATUS);
    MouseShow;
    ReadKeyBIOS(Scan);
    RestoreArea(14, 9, 66, 15, Saved);
    Exit;
  end;

  Saved := SaveArea(14, 7, 66, 17);
  MouseHide;
  FillBox(14, 7, 66, 17, ' ', ATTR_DIALOG_BG);
  DrawFrame(14, 7, 66, 17, ATTR_DIALOG_BD, 'Create New Subfolder');

  WriteStr(17, 9,  'Parent: ' + Copy(CurrentPath, 1, 30), ATTR_DIALOG_BG);
  WriteStr(17, 11, 'Enter folder name (up to 8 chars):', ATTR_DIALOG_BG);
  FolderName := '';
  PromptInput(17, 12, FolderName, 8);

  if FolderName = '' then
  begin
    RestoreArea(14, 7, 66, 17, Saved);
    Exit;
  end;

  SanitizeTo83(FolderName, Name8, Ext3);
  if Name8 = '' then
  begin
    RestoreArea(14, 7, 66, 17, Saved);
    Exit;
  end;

  for I := 1 to ItemCount do
  begin
    if Items[I].CleanName = Name8 then
    begin
      WriteStr(17, 14, 'Error: Folder already exists! Any key.', ATTR_DIALOG_HL);
      MouseShow;
      ReadKeyBIOS(Scan);
      RestoreArea(14, 7, 66, 17, Saved);
      Exit;
    end;
  end;

  WriteStr(17, 14, 'Creating subfolder on disk image...', ATTR_DIALOG_HL);

  if not CreateSubdirectory(ActiveImageFile, Layout.DataAreaStart, Layout.BytesPerCluster,
                            Layout.RootDirStart, Layout.RootDirSectors, BPB.SectorsPerCluster,
                            Layout.TotalClusters, @FatBuf, CurrentDirCluster,
                            Name8, ErrMsg) then
  begin
    WriteStr(17, 14, PadRight('Error: ' + Copy(ErrMsg, 1, 30) + '! Any key.', 46), ATTR_DIALOG_HL);
    MouseShow;
    ReadKeyBIOS(Scan);
  end
  else
  begin
    FlushFAT;
    CalculateFreeSpace;
    LoadBootAndBPB;
    ReadCurrentDirectory;
    WriteStr(17, 14, PadRight('Folder ' + Name8 + ' created! Any key.', 46), ATTR_DIALOG_HL);
    MouseShow;
    ReadKeyBIOS(Scan);
  end;

  RestoreArea(14, 7, 66, 17, Saved);
end;

procedure MakeDiskPCCompatibleModal;
var
  Saved: PPopupSave;
  Ch: Char;
  Scan: Byte;
  MX, MY: Integer;
  DblClick: Boolean;
  ActualW: Word;
  ActiveBtn: Integer;
  Event: Integer;
begin
  if (not ImageIsOpen) or (ActiveImagePath = '') then Exit;

  if ImageIsReadOnly then
  begin
    Saved := SaveArea(14, 9, 66, 15);
    MouseHide;
    FillBox(14, 9, 66, 15, ' ', ATTR_DIALOG_BG);
    DrawFrame(14, 9, 66, 15, ATTR_DIALOG_BD, 'Make PC Compatible');
    WriteStr(17, 11, 'Cannot patch: Image is read-only!', ATTR_DIALOG_HL);
    WriteStr(17, 13, 'Press any key to return...', ATTR_STATUS);
    MouseShow;
    ReadKeyBIOS(Scan);
    RestoreArea(14, 9, 66, 15, Saved);
    Exit;
  end;

  Saved := SaveArea(8, 4, 72, 20);
  MouseHide;
  FillBox(8, 4, 72, 20, ' ', ATTR_DIALOG_BG);
  DrawFrame(8, 4, 72, 20, ATTR_DIALOG_BD, ' Make Disk PC / MS-DOS Compatible ');

  WriteStr(11, 6,  'This operation patches the Atari ST Boot Sector to allow', ATTR_DIALOG_BG);
  WriteStr(11, 7,  'standard MS-DOS and Windows PCs to read this floppy disk:', ATTR_DIALOG_BG);
  WriteStr(11, 9,  '- Installs PC jump instruction ($EB $3C $90 / JMP SHORT $3C)', ATTR_DIALOG_HL);
  WriteStr(11, 10, '- Sets standard DOS OEM ID: ''MSDOS5.0''', ATTR_DIALOG_HL);
  WriteStr(11, 11, '- Sets extended BPB ($29) with Volume Serial & Label', ATTR_DIALOG_HL);
  WriteStr(11, 12, '- Adds standard PC boot signature ($55 $AA) at sector tail', ATTR_DIALOG_HL);
  WriteStr(11, 13, '- Preserves Atari cluster geometry and TOS bootability', ATTR_DIALOG_HL);

  WriteStr(11, 15, 'Do you want to apply the PC-compatibility patch now?', ATTR_DIALOG_BG);

  ActiveBtn := 0;
  repeat
    MouseHide;
    if ActiveBtn = 0 then
    begin
      WriteStr(16, 17, '[  Apply Patch (Y)  ]', ATTR_MENU_SEL);
      WriteStr(44, 17, '[ Cancel (Esc) ]', ATTR_DIALOG_HL);
    end
    else
    begin
      WriteStr(16, 17, '[  Apply Patch (Y)  ]', ATTR_DIALOG_HL);
      WriteStr(44, 17, '[ Cancel (Esc) ]', ATTR_MENU_SEL);
    end;
    MouseShow;

    Event := GetInputEvent(Ch, Scan, MX, MY, DblClick);
    if Event = EVENT_KEY then
    begin
      if (Ch = #27) or (UpCase(Ch) = 'N') or (Scan = KEY_F10) then Break;
      if (Ch = #9) or (Scan = KEY_TAB) or (Scan = KEY_LEFT) or (Scan = KEY_RIGHT) then
        ActiveBtn := 1 - ActiveBtn
      else if UpCase(Ch) = 'Y' then
      begin
        ActiveBtn := 0;
      end
      else if (Ch = #13) or (Ch = ' ') then
      begin
        if ActiveBtn = 1 then Break;
      end
      else
        Continue;
    end
    else if Event = EVENT_CLICK then
    begin
      if (MY = 17) and (MX >= 16) and (MX <= 38) then
        ActiveBtn := 0
      else if (MY = 17) and (MX >= 44) and (MX <= 60) then
        Break
      else if (MX < 8) or (MX > 72) or (MY < 4) or (MY > 20) then
        Break
      else
        Continue;
    end;

    if ActiveBtn = 0 then
    begin
      MouseHide;
      MakePCBootData(RawBootSector);
      Seek(ActiveImageFile, 0);
      BlockWrite(ActiveImageFile, RawBootSector, 512, ActualW);
      LoadBootAndBPB;
      WriteStr(11, 15, 'Patch Applied Successfully! Disk is now PC-Compatible.', ATTR_DIALOG_HL);
      WriteStr(11, 17, 'Press any key or click to return...                   ', ATTR_STATUS);
      MouseShow;
      GetInputEvent(Ch, Scan, MX, MY, DblClick);
      Break;
    end;
  until False;

  MouseHide;
  RestoreArea(8, 4, 72, 20, Saved);
  MouseShow;
end;

procedure ShowBPBModal;
var
  Scan: Byte;
  Saved: PPopupSave;
begin
  Saved := SaveArea(8, 3, 72, 21);
  FillBox(8, 3, 72, 21, ' ', ATTR_DIALOG_BG);
  DrawFrame(8, 3, 72, 21, ATTR_DIALOG_BD, 'Atari ST Disk & BPB Inspector');

  WriteStr(11, 5,  'Image File:       ' + Copy(ActiveImagePath, 1, 42), ATTR_DIALOG_HL);
  WriteStr(11, 6,  'Capacity:         ' + FormatNum(Layout.TotalBytes) + ' B (' +
    IntToStr(Layout.TotalBytes div 1024) + ' KB)', ATTR_DIALOG_BG);
  WriteStr(11, 7,  'Free Space:       ' + FormatNum(Layout.FreeBytes)  + ' B (' +
    IntToStr(Layout.FreeClusters) + ' clust)', ATTR_DIALOG_BG);
  WriteStr(11, 8,  'OEM / TOS Tag:    ''' + BPB.OEMName + '''', ATTR_DIALOG_BG);
  WriteStr(11, 9,  'Atari Serial #:   $' + HexStrWord(BPB.DiskSerial shr 8) +
    HexStrByte(BPB.DiskSerial and $FF), ATTR_DIALOG_BG);
  WriteStr(11, 10, 'Tracks / Heads:   80 Tracks, ' + IntToStr(BPB.Sides) + ' Head(s)', ATTR_DIALOG_BG);
  WriteStr(11, 11, 'Sectors Per Track:' + IntToStr(BPB.SectorsPerTrack) + ' sectors', ATTR_DIALOG_BG);
  WriteStr(11, 12, 'Bytes Per Sector: ' + IntToStr(BPB.BytesPerSector) + ' bytes', ATTR_DIALOG_BG);
  WriteStr(11, 13, 'Cluster Size:     ' + IntToStr(BPB.SectorsPerCluster) + ' sec (' +
    IntToStr(Layout.BytesPerCluster) + ' B)', ATTR_DIALOG_BG);
  WriteStr(11, 14, 'FAT Copies / Size:' + IntToStr(BPB.NumberOfFATs) + ' FAT(s), ' +
    IntToStr(BPB.SectorsPerFAT) + ' sec', ATTR_DIALOG_BG);
  WriteStr(11, 15, 'Root Dir Entries: ' + IntToStr(BPB.RootEntries) + ' max entries', ATTR_DIALOG_BG);
  WriteStr(11, 16, 'Media Descriptor: $' + HexStrByte(BPB.MediaDescriptor), ATTR_DIALOG_BG);
  WriteStr(11, 17, 'Boot Checksum:    $' + HexStrWord(BPB.BootChecksum), ATTR_DIALOG_BG);

  if BPB.IsExecBoot then
    WriteStr(11, 18, 'Executable Boot:  [YES] (Atari executes boot code)', ATTR_NORMAL)
  else
    WriteStr(11, 18, 'Executable Boot:  [NO] (Non-bootable data disk)', ATTR_DIALOG_BG);

  WriteStr(24, 20, 'Press any key to close...', ATTR_DIALOG_HL);
  ReadKeyBIOS(Scan);
  RestoreArea(8, 3, 72, 21, Saved);
end;

{===========================================================================}
{   MAIN USER INTERFACE & RENDERING                                         }
{===========================================================================}

procedure RenderScreen;
var
  I, RowY, DisplayIdx: Integer;
  Attr: Byte;
  LineStr: string;
  PercentFree: LongInt;
  InfoStr: string;
  AttrStr: string[6];
  DateStr: string[10];
  TimeStr: string[8];
begin
  { 1. Top Menu Bar (Row 0) }
  DrawMenuBar(0);

  { 2. Image Status Subheader (Row 1) }
  if ImageIsOpen then
  begin
    if Layout.TotalBytes > 0 then
      PercentFree := (Layout.FreeBytes * 100) div Layout.TotalBytes
    else
      PercentFree := 0;

    if IsTempZip then
      InfoStr := ' ' + Copy(ActiveImagePath, 1, 34) + ' [ZIP, ' + IntToStr(Layout.TotalBytes div 1024) + 'K, ' +
                 IntToStr(BPB.Sides) + 'S, ' + IntToStr(BPB.SectorsPerTrack) + 'T] ' +
                 'Free: ' + IntToStr(Layout.FreeBytes div 1024) + ' KB (' + IntToStr(PercentFree) + '%)'
    else if IsTempMSA then
      InfoStr := ' ' + Copy(ActiveImagePath, 1, 34) + ' [MSA, ' + IntToStr(Layout.TotalBytes div 1024) + 'K, ' +
                 IntToStr(BPB.Sides) + 'S, ' + IntToStr(BPB.SectorsPerTrack) + 'T] ' +
                 'Free: ' + IntToStr(Layout.FreeBytes div 1024) + ' KB (' + IntToStr(PercentFree) + '%)'
    else if IsTempDIM then
      InfoStr := ' ' + Copy(ActiveImagePath, 1, 34) + ' [DIM, ' + IntToStr(Layout.TotalBytes div 1024) + 'K, ' +
                 IntToStr(BPB.Sides) + 'S, ' + IntToStr(BPB.SectorsPerTrack) + 'T] ' +
                 'Free: ' + IntToStr(Layout.FreeBytes div 1024) + ' KB (' + IntToStr(PercentFree) + '%)'
    else
      InfoStr := ' ' + Copy(ActiveImagePath, 1, 38) + ' [' + IntToStr(Layout.TotalBytes div 1024) + 'K, ' +
                 IntToStr(BPB.Sides) + 'S, ' + IntToStr(BPB.SectorsPerTrack) + 'T] ' +
                 'Free: ' + IntToStr(Layout.FreeBytes div 1024) + ' KB (' + IntToStr(PercentFree) + '%)';
    WriteStr(0, 1, PadRight(Copy(InfoStr, 1, 80), 80), ATTR_HEADER);
  end
  else
  begin
    WriteStr(0, 1, PadRight(' No image loaded. Press [O] or F10 for menu to open an image.', 80), ATTR_HEADER);
  end;

  { 3. Main File List Frame (Left side: Cols 0..53, Rows 2..24 - 19 rows visible!) }
  DrawFrame(0, 2, 53, 24, ATTR_BORDER, 'Directory: ' + CurrentPath);
  WriteStr(1, 3, PadRight(' Name             Size Attr   Date    Time  Clust  ', 52), ATTR_HEADER);
  WriteCell(0, 4, #195, ATTR_BORDER);
  for I := 1 to 52 do WriteCell(I, 4, #196, ATTR_BORDER);
  WriteCell(53, 4, #180, ATTR_BORDER);

  for RowY := 0 to 18 do
  begin
    DisplayIdx := TopIdx + RowY;
    if (DisplayIdx >= 1) and (DisplayIdx <= ItemCount) then
    begin
      if DisplayIdx = SelectedIdx then
      begin
        if Items[DisplayIdx].IsDeleted then
          Attr := ATTR_DEL_SEL
        else if Items[DisplayIdx].IsDir then
          Attr := ATTR_DIR_SEL
        else if Items[DisplayIdx].IsHidden then
          Attr := ATTR_HID_SEL
        else
          Attr := ATTR_SELECTED;
      end
      else
      begin
        if Items[DisplayIdx].IsDeleted then
          Attr := ATTR_DELETED
        else if Items[DisplayIdx].IsDir then
          Attr := ATTR_DIR
        else if Items[DisplayIdx].IsHidden then
          Attr := ATTR_HIDDEN
        else
          Attr := ATTR_NORMAL;
      end;

      LineStr := ' ' + PadRight(Items[DisplayIdx].DisplayName, 12) + ' ';
      if Items[DisplayIdx].IsDir then
        LineStr := LineStr + '   <DIR> '
      else
        LineStr := LineStr + PadLeft(FormatNum(Items[DisplayIdx].Size), 8) + ' ';

      if Items[DisplayIdx].IsDeleted then
        AttrStr := '*d* '
      else if Items[DisplayIdx].IsHidden then
        AttrStr := '*h* '
      else if (Items[DisplayIdx].Attr and $01) <> 0 then
        AttrStr := ' R  '
      else
        AttrStr := '    ';
      LineStr := LineStr + AttrStr + ' ';

      if (Items[DisplayIdx].Month >= 1) and (Items[DisplayIdx].Month <= 12) and
         (Items[DisplayIdx].Day >= 1) and (Items[DisplayIdx].Day <= 31) then
        DateStr := TwoDigits(Items[DisplayIdx].Year) + '-' +
                   TwoDigits(Items[DisplayIdx].Month) + '-' +
                   TwoDigits(Items[DisplayIdx].Day)
      else
        DateStr := '--------';
      LineStr := LineStr + DateStr + '  ';

      TimeStr := TwoDigits(Items[DisplayIdx].Hour) + ':' +
                 TwoDigits(Items[DisplayIdx].Min);
      LineStr := LineStr + TimeStr + '  ';

      LineStr := LineStr + PadLeft(IntToStr(Items[DisplayIdx].StartCluster), 5) + '  ';

      WriteStr(1, 5 + RowY, PadRight(LineStr, 52), Attr);
    end
    else
    begin
      WriteStr(1, 5 + RowY, PadRight('', 52), ATTR_NORMAL);
    end;
  end;

  { 4. Right Side Inspector Box (Cols 54..79, Rows 2..24) }
  DrawFrame(54, 2, 79, 24, ATTR_BORDER, 'Disk & File Info');
  FillBox(55, 3, 78, 23, ' ', ATTR_NORMAL);
  if ImageIsOpen then
  begin
    WriteStr(56, 4,  'OEM:      ' + BPB.OEMName, ATTR_STATUS);
    WriteStr(56, 5,  'Serial:   $' + HexStrWord(BPB.DiskSerial shr 8) +
      HexStrByte(BPB.DiskSerial and $FF), ATTR_STATUS);
    WriteStr(56, 6,  'Capacity: ' + IntToStr(Layout.TotalBytes div 1024) + ' KB', ATTR_STATUS);
    WriteStr(56, 7,  'Sides:    ' + IntToStr(BPB.Sides), ATTR_STATUS);
    WriteStr(56, 8,  'Sec/Trk:  ' + IntToStr(BPB.SectorsPerTrack), ATTR_STATUS);
    WriteStr(56, 9,  'Sec/Clust:' + IntToStr(BPB.SectorsPerCluster), ATTR_STATUS);
    WriteStr(56, 10, 'Cluster:  ' + IntToStr(Layout.BytesPerCluster) + ' bytes', ATTR_STATUS);
    WriteStr(56, 11, 'TotalSec: ' + IntToStr(BPB.TotalSectors), ATTR_STATUS);
    WriteStr(56, 12, 'FAT Size: ' + IntToStr(BPB.SectorsPerFAT) + ' sectors', ATTR_STATUS);
    WriteStr(56, 13, 'RootDir:  ' + IntToStr(BPB.RootEntries) + ' items', ATTR_STATUS);
    WriteStr(56, 14, 'TotalClu: ' + IntToStr(Layout.TotalClusters), ATTR_STATUS);
    WriteStr(56, 15, 'FreeClu:  ' + IntToStr(Layout.FreeClusters), ATTR_STATUS);
    WriteStr(56, 16, 'MediaDesc:$' + HexStrByte(BPB.MediaDescriptor), ATTR_STATUS);
    WriteStr(56, 17, 'BootSum:  $' + HexStrWord(BPB.BootChecksum), ATTR_STATUS);
    if BPB.IsExecBoot then
      WriteStr(56, 18, 'Bootable: [YES] (Auto)', ATTR_HEADER)
    else
      WriteStr(56, 18, 'Bootable: [NO] (Data)', ATTR_STATUS);
    WriteStr(56, 19, 'Boot:[B]  Virus:[S]', ATTR_HEADER);

    { Selected item details & detected compression tag }
    if (SelectedIdx >= 1) and (SelectedIdx <= ItemCount) then
    begin
      WriteStr(56, 20, 'Packer: ' + PadRight(Items[SelectedIdx].PackerTag, 14), ATTR_HEADER);
      WriteStr(56, 21, 'Sel: ' + IntToStr(SelectedIdx) + '/' + IntToStr(ItemCount), ATTR_STATUS);
      WriteStr(56, 22, 'Clust: #' + IntToStr(Items[SelectedIdx].StartCluster), ATTR_STATUS);
      WriteStr(56, 23, 'Size:  ' + FormatNum(Items[SelectedIdx].Size) + ' B', ATTR_STATUS);
    end
    else
    begin
      WriteStr(56, 20, 'Files in Dir: ' + IntToStr(ItemCount), ATTR_HEADER);
      WriteStr(56, 21, PadRight('', 22), ATTR_STATUS);
      WriteStr(56, 22, PadRight('', 22), ATTR_STATUS);
      WriteStr(56, 23, PadRight('', 22), ATTR_STATUS);
    end;
  end
  else
  begin
    WriteStr(56, 5,  'No Image Loaded', ATTR_STATUS);
    WriteStr(56, 7,  'Press [O] to Open', ATTR_HEADER);
    WriteStr(56, 8,  'Press [F9] for New', ATTR_HEADER);
    WriteStr(56, 9,  'Press [F1] for Help', ATTR_STATUS);
    for I := 10 to 23 do
      WriteStr(56, I, PadRight('', 22), ATTR_STATUS);
  end;
end;

procedure HandleEnterKey;
var
  Ext: string[4];
  I: Integer;
begin
  if (ItemCount = 0) or (SelectedIdx < 1) or (SelectedIdx > ItemCount) then Exit;

  if Items[SelectedIdx].IsDir then
  begin
    if Items[SelectedIdx].DisplayName = '..' then
    begin
      CurrentDirCluster := Items[SelectedIdx].StartCluster;
      if Length(CurrentPath) > 1 then
      begin
        if CurrentPath[Length(CurrentPath)] = '\' then
          Dec(CurrentPath[0]);
        while (Length(CurrentPath) > 1) and (CurrentPath[Length(CurrentPath)] <> '\') do
          Dec(CurrentPath[0]);
      end;
      if (CurrentPath = '') or (CurrentPath[Length(CurrentPath)] <> '\') then
        CurrentPath := CurrentPath + '\';
      SelectedIdx := 1;
      TopIdx := 1;
      ReadCurrentDirectory;
    end
    else
    begin
      { Enter Subdirectory }
      CurrentDirCluster := Items[SelectedIdx].StartCluster;
      CurrentPath := CurrentPath + Items[SelectedIdx].CleanName + '\';
      SelectedIdx := 1;
      TopIdx := 1;
      ReadCurrentDirectory;
    end;
  end
  else
  begin
    Ext := '';
    if Length(Items[SelectedIdx].CleanName) >= 4 then
      Ext := Copy(Items[SelectedIdx].CleanName, Length(Items[SelectedIdx].CleanName) - 3, 4);
    for I := 1 to Length(Ext) do Ext[I] := UpCase(Ext[I]);

    if (Ext = '.PC1') or (Ext = '.PC2') or (Ext = '.PC3') or
       (Ext = '.PI1') or (Ext = '.PI2') or (Ext = '.PI3') or
       (Ext = '.DEG') or (Ext = '.NEO') or (Ext = '.ART') or
       (Ext = '.DOO') or (Ext = '.SCR') or (Ext = '.PAC') or
       (Ext = '.BMP') or (Ext = '.GIF') or (Ext = '.JPG') or (Ext = '.PNG') then
      ViewImageGraphic
    else
      ViewFileText;
  end;
end;

procedure EventLoop;
var
  Ch: Char;
  Scan: Byte;
  MX, MY: Integer;
  DblClick: Boolean;
  Event: Integer;
  PickedFile: string;
  ClickedIdx: Integer;
begin
  Running := True;
  while Running do
  begin
    MouseHide;
    RenderScreen;
    MouseShow;

    Event := GetInputEvent(Ch, Scan, MX, MY, DblClick);

    if Event = EVENT_CLICK then
    begin
      if MY = 0 then
      begin
        if (MX >= MenuX[1]) and (MX <= MenuX[1] + 7) then
          ExecuteDropdownMenu(1)
        else if (MX >= MenuX[2]) and (MX <= MenuX[2] + 8) then
          ExecuteDropdownMenu(2)
        else if (MX >= MenuX[3]) and (MX <= MenuX[3] + 7) then
          ExecuteDropdownMenu(3)
        else if (MX >= MenuX[4]) and (MX <= MenuX[4] + 7) then
          ExecuteDropdownMenu(4);
      end
      else if (MY >= 5) and (MY <= 23) and (MX >= 1) and (MX <= 53) then
      begin
        ClickedIdx := TopIdx + (MY - 5);
        if (ClickedIdx >= 1) and (ClickedIdx <= ItemCount) then
        begin
          if (ClickedIdx = SelectedIdx) and DblClick then
            HandleEnterKey
          else
            SelectedIdx := ClickedIdx;
        end;
      end;
    end
    else if Event = EVENT_KEY then
    begin
      if Ch = #0 then
      begin
      { Extended BIOS Function Keys & Alt Keys }
      case Scan of
        KEY_UP:
          begin
            if SelectedIdx > 1 then
            begin
              Dec(SelectedIdx);
              if SelectedIdx < TopIdx then TopIdx := SelectedIdx;
            end;
          end;
        KEY_DOWN:
          begin
            if SelectedIdx < ItemCount then
            begin
              Inc(SelectedIdx);
              if SelectedIdx >= TopIdx + 19 then
                TopIdx := SelectedIdx - 18;
            end;
          end;
        KEY_PAGEUP:
          begin
            SelectedIdx := SelectedIdx - 18;
            if SelectedIdx < 1 then SelectedIdx := 1;
            TopIdx := TopIdx - 18;
            if TopIdx < 1 then TopIdx := 1;
          end;
        KEY_PAGEDOWN:
          begin
            SelectedIdx := SelectedIdx + 18;
            if SelectedIdx > ItemCount then SelectedIdx := ItemCount;
            TopIdx := TopIdx + 18;
            if TopIdx > ItemCount - 18 then TopIdx := ItemCount - 18;
            if TopIdx < 1 then TopIdx := 1;
          end;
        KEY_HOME:
          begin
            SelectedIdx := 1;
            TopIdx := 1;
          end;
        KEY_END:
          begin
            SelectedIdx := ItemCount;
            TopIdx := ItemCount - 18;
            if TopIdx < 1 then TopIdx := 1;
          end;
        KEY_DELETE:
          DeleteActiveFile;
        KEY_F1:
          ShowHelpModal;
        KEY_F2:
          ShowBPBModal;
        KEY_F3:
          InteractiveFileViewer(False);
        KEY_F4:
          InteractiveFileViewer(True);
        KEY_F5:
          ExtractActiveFile;
        KEY_F6:
          ShowClusterMapModal;
        KEY_F8:
          DeleteActiveFile;
        KEY_F9:
          CreateBlankDisk;
        KEY_F10:
          ExecuteDropdownMenu(1);
        KEY_ALT_F:
          ExecuteDropdownMenu(1);
        KEY_ALT_I:
          ExecuteDropdownMenu(2);
        KEY_ALT_V:
          ExecuteDropdownMenu(3);
        KEY_ALT_H:
          ExecuteDropdownMenu(4);
        KEY_ALT_X:
          Running := False;
      end;
    end
    else
    begin
      { Standard ASCII Keys }
      case UpCase(Ch) of
        #13: HandleEnterKey;
        #8:  { Backspace: go up to parent directory }
             begin
               if CurrentDirCluster <> 0 then
               begin
                 if (ItemCount >= 1) and (Items[1].DisplayName = '..') then
                   CurrentDirCluster := Items[1].StartCluster
                 else
                   CurrentDirCluster := 0;
                 if Length(CurrentPath) > 1 then
                 begin
                   if CurrentPath[Length(CurrentPath)] = '\' then
                     Dec(CurrentPath[0]);
                   while (Length(CurrentPath) > 1) and (CurrentPath[Length(CurrentPath)] <> '\') do
                     Dec(CurrentPath[0]);
                 end;
                 if (CurrentPath = '') or (CurrentPath[Length(CurrentPath)] <> '\') then
                   CurrentPath := CurrentPath + '\';
                 SelectedIdx := 1;
                 TopIdx := 1;
                 ReadCurrentDirectory;
               end;
             end;
        'O': begin if ShowFileDialog(PickedFile) then OpenImage(PickedFile); end;
        'U': UndeleteActiveFile;
        'B': ShowBootSectorHexModal;
        'S': ShowVirusScannerModal;
        'K': MakeDiskPCCompatibleModal;
        'M': ShowClusterMapModal;
        'W': WriteImageToFloppyModal;
        'L': ReadFloppyToImageModal;
        'P': DepackActiveFile(False);
        'Z': ExtractAllAsZip;
        'V': InteractiveFileViewer(True);
        'H': InteractiveFileViewer(True);
        'T': InteractiveFileViewer(False);
        'E': ExtractActiveFile;
        'D': DeleteActiveFile;
        'N': CreateBlankDisk;
        'R': ReadCurrentDirectory;
        'C': CloseImage;
        'F': ShowSearchModal;
        'X': ShowCatalogModal;
        'I': ShowImportFileModal;
        '+': ShowMkdirModal;
        '?': ShowHelpModal;
        'A': ShowAboutModal;
        'Q': Running := False;
      end;
    end;
  end;
  end;
end;

{===========================================================================}
{   MAIN PROGRAM ENTRY POINT                                                }
{===========================================================================}

var
  InitialArg: string;

begin
  AppDir := GetApplicationDir;
  HideCursor;
  MouseInit;
  MouseShow;
  ImageIsOpen := False;
  ItemCount := 0;

  { If an image file was supplied on the command line, open it immediately }
  if ParamCount > 0 then
  begin
    InitialArg := ParamStr(1);
    OpenImage(InitialArg);
  end
  else
  begin
    { If no image was given on startup, immediately show the file dialog! }
    if ShowFileDialog(InitialArg) then
      OpenImage(InitialArg);
  end;

  EventLoop;

  CloseImage;

  { Restore cursor & clear screen on exit }
  MouseHide;
  FillBox(0, 0, 79, 24, ' ', $07);
  SetCursorPos(0, 0);
  ShowCursor;
  WriteLn('STIMAGE for MS-DOS terminated normally.');
end.
