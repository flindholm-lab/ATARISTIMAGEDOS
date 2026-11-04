{===========================================================================}
{   DISKTOOL.PAS - Extended Disk Operations Unit for STIMAGE DOS             }
{   FastCopy Pro .DIM support, Search, Catalog Export (TXT/CSV), FAT12 Tools }
{   Turbo Pascal 7.0 Real-Mode Compatible - Lines strictly <= 120 chars      }
{===========================================================================}
unit DiskTool;

{$F+,R-,S-,I-,V-,A-}

interface

uses Dos, Depack;

const
  DIM_MAGIC           = $4242; { 'BB' FastCopy Pro ID }
  MAX_SEARCH_RESULTS  = 120;
  FAT12_EOC_MIN       = $0FF8;
  FAT12_EOC           = $0FFF;
  FAT12_FREE          = $0000;
  ATARI_BOOT_EXEC_SUM = $1234;

type
  PByteArray = ^TByteArray;
  TByteArray = array[0..32767] of Byte;
  TString12 = string[12];
  TString80 = string[80];

  { Atari ST Boot Sector & BPB (BIOS Parameter Block) }
  TAtariBPB = record
    BytesPerSector: Word;
    SectorsPerCluster: Byte;
    ReservedSectors: Word;
    NumberOfFATs: Byte;
    RootEntries: Word;
    TotalSectors: Word;
    MediaDescriptor: Byte;
    SectorsPerFAT: Word;
    SectorsPerTrack: Word;
    Sides: Word;
    HiddenSectors: Word;
    DiskSerial: LongInt;     { 24-bit serial at $08..$0A }
    OEMName: string[6];
    BootChecksum: Word;
    IsExecBoot: Boolean;
    IsPlausible: Boolean;
  end;

  { Calculated Layout Geometry }
  TDiskLayout = record
    FatTableStart: LongInt;
    SingleFATSize: LongInt;
    RootDirStart: LongInt;
    RootDirSectors: Word;
    RootDirBytes: LongInt;
    DataAreaStart: LongInt;
    BytesPerCluster: Word;
    TotalClusters: Word;
    FreeClusters: Word;
    TotalBytes: LongInt;
    FreeBytes: LongInt;
    Sides: Word;
    Tracks: Word;
    SectorsPerTrack: Word;
    TotalSectors: Word;
  end;

  { File / Directory Entry }
  TDiskItem = record
    DisplayName: TString12;
    CleanName: TString12;
    Size: LongInt;
    Attr: Byte;
    StartCluster: Word;
    Year, Month, Day: Word;
    Hour, Min, Sec: Word;
    IsDir: Boolean;
    IsDeleted: Boolean;
    IsHidden: Boolean;
    EntryOffset: LongInt;
    PackerTag: string[14];  { Detected packer signature }
  end;

  { FastCopy Pro 32-byte Disk Image Header }
  TDIMHeader = packed record
    ID: Word;               { $4242 ('BB') }
    AutoDetect: Byte;
    SectorMode: Byte;       { 0 = all sectors, 1 = sparse/used only }
    Reserved1: Word;
    Sides: Byte;            { 0 = 1 side, 1 = 2 sides }
    Reserved2: Byte;
    SectorsPerTrack: Byte;  { 9, 10, 11, 18, etc. }
    Reserved3: Byte;
    StartTrack: Byte;
    Reserved4: Byte;
    EndTrack: Byte;
    Density: Byte;
    BPB: array[0..17] of Byte;
  end;

  TSearchRecord = record
    DirPath: string[36];
    Name: string[12];
    Size: LongInt;
    Attr: Byte;
    StartCluster: Word;
    ParentCluster: Word;
    IsDir: Boolean;
    Year, Month, Day: Word;
    Hour, Min: Word;
  end;

  TSearchArray = array[0..MAX_SEARCH_RESULTS - 1] of TSearchRecord;
  PSearchArray = ^TSearchArray;

{ FastCopy Pro .DIM Support }
function  IsDIMFile(const Path: string): Boolean;
function  UnpackDIMToFile(const DimFileName, OutSTFileName: string): Boolean;

{ Wildcard Matching }
function  WildcardMatch(Pattern, Target: string): Boolean;

{ Formatting Utilities }
function  FormatFileSize(Bytes: LongInt): string;
function  FormatAttr(Attr: Byte): string;
function  SanitizeTo83(const InputName: string; var Name8, Ext3: string): Boolean;
procedure GetCurrentDosTimeDate(var FTime, FDate: Word);

{ FAT12 Helpers }
function  GetFat12Entry(FatBuf: PByteArray; Cluster: Word): Word;
procedure SetFat12Entry(FatBuf: PByteArray; Cluster, Value: Word);

{ Recursive Disk Search }
function  SearchDiskRecursive(var ImgF: file; DataAreaStart: LongInt;
  BytesPerCluster: Word; RootDirStart: LongInt; RootDirSectors: Word;
  SectorsPerCluster: Byte; FatBuf: Pointer; const Pattern: string;
  var Results: array of TSearchRecord; MaxResults: Integer): Integer;

{ Catalog Export (Text & CSV) }
function  ExportCatalogFile(var ImgF: file; DataAreaStart: LongInt;
  BytesPerCluster: Word; RootDirStart: LongInt; RootDirSectors: Word;
  SectorsPerCluster: Byte; TotalClusters, FreeClusters: Word;
  Tracks, Sides, SectorsPerTrack: Word; TotalBytes, FreeBytes: LongInt;
  FatBuf: Pointer; const ImgPath, OutPath: string; AsCSV: Boolean): Boolean;

{ File Import & Subdirectory Management }
function  ImportDosFile(var ImgF: file; DataAreaStart: LongInt;
  BytesPerCluster: Word; RootDirStart: LongInt; RootDirSectors: Word;
  SectorsPerCluster: Byte; TotalClusters: Word; FatBuf: Pointer;
  CurrentDirClust: Word; const DosFilePath, TargetName: string;
  var ErrMsg: string): Boolean;

function  CreateSubdirectory(var ImgF: file; DataAreaStart: LongInt;
  BytesPerCluster: Word; RootDirStart: LongInt; RootDirSectors: Word;
  SectorsPerCluster: Byte; TotalClusters: Word; FatBuf: Pointer;
  CurrentDirClust: Word; const SubdirName: string;
  var ErrMsg: string): Boolean;

function  RenameDirEntry(var ImgF: file; EntryOffset: LongInt;
  const NewName8, NewExt3: string): Boolean;
function  UpdateDirEntryAttr(var ImgF: file; EntryOffset: LongInt;
  NewAttr: Byte): Boolean;


type
  TBigByteArray = array[0..65520] of Byte;
  PBigByteArray = ^TBigByteArray;

  TZipLFH = packed record
    Sig: LongInt;        { $04034B50 }
    VerNeeded: Word;     { 20 }
    Flags: Word;         { 0 }
    Method: Word;        { 0 = store }
    ModTime: Word;
    ModDate: Word;
    CRC32: LongInt;
    CompSize: LongInt;
    UncompSize: LongInt;
    NameLen: Word;
    ExtraLen: Word;
  end;

  TZipCDH = packed record
    Sig: LongInt;        { $02014B50 }
    VerMadeBy: Word;     { 20 }
    VerNeeded: Word;     { 20 }
    Flags: Word;         { 0 }
    Method: Word;        { 0 }
    ModTime: Word;
    ModDate: Word;
    CRC32: LongInt;
    CompSize: LongInt;
    UncompSize: LongInt;
    NameLen: Word;
    ExtraLen: Word;
    CommentLen: Word;
    DiskStart: Word;
    IntAttr: Word;
    ExtAttr: LongInt;
    LocalHdrOffset: LongInt;
  end;

  TZipEOCD = packed record
    Sig: LongInt;        { $06054B50 }
    DiskNum: Word;
    StartDisk: Word;
    TotalEntriesDisk: Word;
    TotalEntries: Word;
    CDSize: LongInt;
    CDOffset: LongInt;
    CommentLen: Word;
  end;

  TZipWriteEntry = record
    RelPath: string[64];
    DosName: string[12];
    StartCluster: Word;
    FileSize: LongInt;
    Attr: Byte;
    TimeWord: Word;
    DateWord: Word;
    LFHOffset: LongInt;
    Crc32: LongInt;
    CompSize: LongInt;
    UncompSize: LongInt;
  end;
  TZipWriteArray = array[1..350] of TZipWriteEntry;
  PZipWriteArray = ^TZipWriteArray;

function  AtariBootChecksum(Buf: Pointer): Word;
function  FindSig(Buf: Pointer; Len: Integer; const Sig: string): Boolean;
function  DetectPacker(Buf: Pointer; Size: Integer): string;
function  UnpackMSAToFile(const MSAFileName, OutSTFileName: string): Boolean;
procedure InitCRC32;
function  UpdateCRC32(Crc: LongInt; const Buf; Len: Word): LongInt;
function  BiosDiskReset(Drive: Byte): Byte;
function  BiosWriteSectors(Drive, Head, Track, Sector, Count: Byte; var Buffer): Byte;
function  BiosReadSectors(Drive, Head, Track, Sector, Count: Byte; var Buffer): Byte;
function  BiosDriveType(Drive: Byte): Byte;
function  BiosDiskErrorStr(Code: Byte): string;
function  FloppyBufAlloc: Pointer;
procedure FloppyBufFree;
function  FloppyDetectGeometry(Drive: Byte; Buf: Pointer; var Sides, SPT, Tracks, TotalSec: Word;
  var Status: Byte): Boolean;
function  FloppyReadTrack(Drive: Byte; Head, Cyl, SPT: Word; Buf: Pointer): Word;
function  CopyFileTo(const Src, Dst: string): Boolean;
procedure EraseFileQuiet(const P: string);
function  ExportDiskAsZip(var ImgF: file; DataAreaStart: LongInt;
  BytesPerCluster: Word; RootDirStart: LongInt; RootDirSectors: Word;
  SectorsPerCluster: Byte; FatBuf: Pointer;
  const TargetZip: string; AutoDepack: Boolean): Boolean;
function  ExtractClusterChainToFile(var ImgF: file; DataAreaStart: LongInt;
  BytesPerCluster: Word; FatBuf: Pointer; StartClust: Word;
  FileSizeVal: LongInt; const DestPath: string): Boolean;
function  ReadClusterChainBytes(var ImgF: file; DataAreaStart: LongInt;
  BytesPerCluster: Word; FatBuf: Pointer; StartCluster: Word;
  FileSizeVal, FileOffset: LongInt; var DestBuf; MaxBytes: Word): Word;
function  FormatBlankDisk(const OutPath: string;
  SidesCount, SecPerTrk, TotalSec: Word): Boolean;
function  ExtractStoredZipMember(const ZipPath: string; LocalOff: LongInt;
  UncompSize: LongInt; const OutPath: string): Boolean;
function  ReadBE16(P: Pointer; Offset: Integer): Word;
function  ReadBE32(P: Pointer; Offset: Integer): LongInt;
function  ReadLE16(P: Pointer; Offset: Integer): Word;
function  ReadLE32(P: Pointer; Offset: Integer): LongInt;
function  HexStrByte(B: Byte): string;
function  HexStrWord(V: Word): string;
function  FormatNum(V: LongInt): string;
function  PadRight(const S: string; W: Integer): string;
function  CanRepackDiskTo720K(var SrcImgF: file; SrcDataStart: LongInt;
  SrcBytesPerClust: Word; SrcRootDirStart: LongInt; SrcRootDirSecs: Word;
  SrcSecPerClust: Byte; SrcFatBuf: Pointer; var TotalClustersNeeded: Word;
  var RootEntriesCount: Word; var TotalFileBytes: LongInt): Boolean;
function  RepackDiskTo720K(var SrcImgF: file; SrcDataStart: LongInt;
  SrcBytesPerClust: Word; SrcRootDirStart: LongInt; SrcRootDirSecs: Word;
  SrcSecPerClust: Byte; SrcFatBuf: Pointer; var SrcBootSector: array of Byte;
  const DestPath: string; var ErrMsg: string): Boolean;
function  PadLeft(const S: string; W: Integer): string;
function  TwoDigits(V: Integer): string;
function  GetApplicationDir: string;
function  ResolveHelperExe(const ExeName, AppDir: string; var FullPath: string): Boolean;
function  ChangeHostDirTracked(const TargetDir: string): Boolean;
function  LoadDiskBootAndBPB(var ImgF: file; var BPB: TAtariBPB;
  var Layout: TDiskLayout; var RawBootSector: array of Byte;
  FatBuf: Pointer; MaxFatBuf: Word): Boolean;
procedure CalcDiskFreeSpace(var Layout: TDiskLayout; FatBuf: Pointer);
procedure FlushDiskFAT(var ImgF: file; const Layout: TDiskLayout;
  NumberOfFATs: Byte; FatBuf: Pointer; MaxFatBuf: Word);
procedure CopyDosFile(const SrcPath, DstPath: string);
function  ParseDirEntry(P: Pointer; FileOffset: LongInt; var Item: TDiskItem): Boolean;
implementation

type
  TRepackQueueItem = record
    SrcClust: Word;
    DstClust: Word;
  end;

var
  CrcTable: array[0..255] of LongInt;
  CrcTableReady: Boolean;
  TrackedRelAppDir: string[80];
  RepackDstBootSec: array[0..511] of Byte;
  RepackZeroBuf: array[0..2047] of Byte;
  RepackFatBuf720: array[0..1535] of Byte;
  RepackQueue: array[1..64] of TRepackQueueItem;
  RepackSectorBuf: array[0..511] of Byte;
  RepackDirEntry: array[0..31] of Byte;
  RepackSubDirBuf: array[0..63] of Byte;
  RepackChunkBuf: array[0..1023] of Byte;
  CanRepackQueue: array[1..64] of Word;
  CanRepackSectorBuf: array[0..511] of Byte;

function ReadBE16(P: Pointer; Offset: Integer): Word;
var
  BA: PByteArray;
begin
  BA := P;
  ReadBE16 := (Word(BA^[Offset]) shl 8) or BA^[Offset + 1];
end;

function HexStrByte(B: Byte): string;
const
  HexChars: array[0..15] of Char = '0123456789ABCDEF';
begin
  HexStrByte := HexChars[B shr 4] + HexChars[B and 15];
end;

function HexStrWord(V: Word): string;
const
  HexChars: array[0..15] of Char = '0123456789ABCDEF';
begin
  HexStrWord := HexChars[(V shr 12) and $0F] +
                HexChars[(V shr 8) and $0F] +
                HexChars[(V shr 4) and $0F] +
                HexChars[V and $0F];
end;

function FormatNum(V: LongInt): string;
var
  Raw, Res: string;
  I, Count: Integer;
begin
  Str(V, Raw);
  Res := '';
  Count := 0;
  for I := Length(Raw) downto 1 do
  begin
    if (Count > 0) and (Count mod 3 = 0) then
      Res := ',' + Res;
    Res := Raw[I] + Res;
    Inc(Count);
  end;
  FormatNum := Res;
end;

function PadRight(const S: string; W: Integer): string;
var
  Res: string;
begin
  Res := S;
  while Length(Res) < W do
    Res := Res + ' ';
  if Length(Res) > W then
    Res := Copy(Res, 1, W);
  PadRight := Res;
end;

function PadLeft(const S: string; W: Integer): string;
var
  Res: string;
begin
  Res := S;
  while Length(Res) < W do
    Res := ' ' + Res;
  if Length(Res) > W then
    Res := Copy(Res, Length(Res) - W + 1, W);
  PadLeft := Res;
end;

function TwoDigits(V: Integer): string;
var
  S: string[4];
begin
  if V < 0 then V := -V;
  V := V mod 100;
  Str(V, S);
  if Length(S) < 2 then S := '0' + S;
  TwoDigits := S;
end;

function ReadLE16(P: Pointer; Offset: Integer): Word;
var
  BA: PByteArray;
begin
  BA := P;
  ReadLE16 := Word(BA^[Offset]) or (Word(BA^[Offset + 1]) shl 8);
end;

function ReadLE32(P: Pointer; Offset: Integer): LongInt;
var
  BA: PByteArray;
  W0, W1: Word;
begin
  BA := P;
  W0 := Word(BA^[Offset]) or (Word(BA^[Offset + 1]) shl 8);
  W1 := Word(BA^[Offset + 2]) or (Word(BA^[Offset + 3]) shl 8);
  ReadLE32 := LongInt(W0) or (LongInt(W1) shl 16);
end;

function ReadBE32(P: Pointer; Offset: Integer): LongInt;
var
  BA: PByteArray;
  W0, W1: Word;
begin
  BA := P;
  W0 := (Word(BA^[Offset]) shl 8) or BA^[Offset + 1];
  W1 := (Word(BA^[Offset + 2]) shl 8) or BA^[Offset + 3];
  ReadBE32 := (LongInt(W0) shl 16) or W1;
end;

function CanOpenFileRead(const FPath: string): Boolean;
var
  TestF: file;
begin
  CanOpenFileRead := False;
  if FPath = '' then Exit;
  if IOResult <> 0 then ;
  Assign(TestF, FPath);
  Reset(TestF, 1);
  if IOResult = 0 then
  begin
    Close(TestF);
    if IOResult <> 0 then ;
    CanOpenFileRead := True;
  end;
end;

function ExtractLastDirLeaf(const DirPath: string): string;
var
  Clean: string;
  I: Integer;
begin
  Clean := DirPath;
  if (Length(Clean) > 1) and ((Clean[Length(Clean)] = '\') or (Clean[Length(Clean)] = '/')) then
    Dec(Clean[0]);
  I := Length(Clean);
  while (I > 0) and (Clean[I] <> '\') and (Clean[I] <> '/') and (Clean[I] <> ':') do
    Dec(I);
  Clean := Copy(Clean, I + 1, Length(Clean) - I);
  if Clean <> '' then
    ExtractLastDirLeaf := Clean + '\'
  else
    ExtractLastDirLeaf := '';
end;

function ResolveHelperExe(const ExeName, AppDir: string; var FullPath: string): Boolean;
var
  LeafDir: string;
begin
  ResolveHelperExe := True;
  LeafDir := ExtractLastDirLeaf(AppDir);
  if (TrackedRelAppDir <> '') and CanOpenFileRead(TrackedRelAppDir + ExeName) then
    FullPath := TrackedRelAppDir + ExeName
  else if CanOpenFileRead(ExeName) then
    FullPath := ExeName
  else if (LeafDir <> '') and CanOpenFileRead(LeafDir + ExeName) then
    FullPath := LeafDir + ExeName
  else if CanOpenFileRead('DOSST\' + ExeName) then
    FullPath := 'DOSST\' + ExeName
  else if CanOpenFileRead('..\' + ExeName) then
    FullPath := '..\' + ExeName
  else if (LeafDir <> '') and CanOpenFileRead('..\' + LeafDir + ExeName) then
    FullPath := '..\' + LeafDir + ExeName
  else if CanOpenFileRead('..\DOSST\' + ExeName) then
    FullPath := '..\DOSST\' + ExeName
  else if CanOpenFileRead('..\..\' + ExeName) then
    FullPath := '..\..\' + ExeName
  else if (LeafDir <> '') and CanOpenFileRead('..\..\' + LeafDir + ExeName) then
    FullPath := '..\..\' + LeafDir + ExeName
  else if CanOpenFileRead('..\..\DOSST\' + ExeName) then
    FullPath := '..\..\DOSST\' + ExeName
  else if (AppDir <> '') and CanOpenFileRead(AppDir + ExeName) then
    FullPath := AppDir + ExeName
  else
  begin
    FullPath := AppDir + ExeName;
    ResolveHelperExe := False;
  end;
end;

function ChangeHostDirTracked(const TargetDir: string): Boolean;
var
  OldDir, Leaf, TDir, Prefix: string;
  I: Integer;
begin
  ChangeHostDirTracked := False;
  if IOResult <> 0 then ;
  GetDir(0, OldDir);
  if IOResult <> 0 then OldDir := '';
  ChDir(TargetDir);
  if IOResult <> 0 then Exit;
  ChangeHostDirTracked := True;

  TDir := TargetDir;
  for I := 1 to Length(TDir) do TDir[I] := UpCase(TDir[I]);

  if TDir = '..' then
  begin
    if Copy(TrackedRelAppDir, 1, 3) = '..\' then
      Delete(TrackedRelAppDir, 1, 3)
    else
    begin
      Leaf := ExtractLastDirLeaf(OldDir);
      if (Leaf <> '') and (Length(Leaf) + Length(TrackedRelAppDir) < 78) then
        TrackedRelAppDir := Leaf + TrackedRelAppDir;
    end;
  end
  else if (TDir <> '.') and (TDir <> '') then
  begin
    Prefix := Copy(TrackedRelAppDir, 1, Length(TDir) + 1);
    for I := 1 to Length(Prefix) do Prefix[I] := UpCase(Prefix[I]);
    if Prefix = TDir + '\' then
      Delete(TrackedRelAppDir, 1, Length(TDir) + 1)
    else if Length(TrackedRelAppDir) < 74 then
      TrackedRelAppDir := '..\' + TrackedRelAppDir;
  end;

  if CanOpenFileRead('VIEW.EXE') then
    TrackedRelAppDir := ''
  else if (TrackedRelAppDir = '') or (not CanOpenFileRead(TrackedRelAppDir + 'VIEW.EXE')) then
  begin
    if CanOpenFileRead('DOSST\VIEW.EXE') then
      TrackedRelAppDir := 'DOSST\'
    else if CanOpenFileRead('..\VIEW.EXE') then
      TrackedRelAppDir := '..\'
    else if CanOpenFileRead('..\DOSST\VIEW.EXE') then
      TrackedRelAppDir := '..\DOSST\'
    else if CanOpenFileRead('..\..\VIEW.EXE') then
      TrackedRelAppDir := '..\..\'
    else if CanOpenFileRead('..\..\DOSST\VIEW.EXE') then
      TrackedRelAppDir := '..\..\DOSST\';
  end;
end;

function GetApplicationDir: string;
var
  P, StartupDir, ParamDir, ShortDir: string;
  I: Integer;

  function CanOpenExe(const DirPath: string): Boolean;
  begin
    CanOpenExe := (DirPath <> '') and CanOpenFileRead(DirPath + 'VIEW.EXE');
  end;

  function TryShortPath(const InPath: string; var OutPath: string): Boolean;
  var
    SrcZ, DstZ: array[0..127] of Char;
    Regs: Registers;
    K: Integer;
    CleanIn: string;
  begin
    TryShortPath := False;
    CleanIn := InPath;
    if (Length(CleanIn) > 3) and (CleanIn[Length(CleanIn)] = '\') then
      Dec(CleanIn[0]);
    if (CleanIn = '') or (Length(CleanIn) > 120) then Exit;
    for K := 1 to Length(CleanIn) do SrcZ[K - 1] := CleanIn[K];
    SrcZ[Length(CleanIn)] := #0;
    FillChar(DstZ, SizeOf(DstZ), 0);
    Regs.AX := $7160;
    Regs.CL := $01;
    Regs.CH := $80;
    Regs.DS := Seg(SrcZ);
    Regs.SI := Ofs(SrcZ);
    Regs.ES := Seg(DstZ);
    Regs.DI := Ofs(DstZ);
    Intr($21, Regs);
    if ((Regs.Flags and 1) = 0) and (Regs.AX <> $7100) and (DstZ[0] <> #0) then
    begin
      OutPath := '';
      K := 0;
      while (K < 78) and (DstZ[K] <> #0) do
      begin
        OutPath := OutPath + DstZ[K];
        Inc(K);
      end;
      if (OutPath <> '') and (OutPath[Length(OutPath)] <> '\') then
        OutPath := OutPath + '\';
      TryShortPath := (OutPath <> '');
    end;
  end;

begin
  TrackedRelAppDir := '';
  if CanOpenFileRead('VIEW.EXE') then
    TrackedRelAppDir := ''
  else if CanOpenFileRead('DOSST\VIEW.EXE') then
    TrackedRelAppDir := 'DOSST\'
  else if CanOpenFileRead('..\VIEW.EXE') then
    TrackedRelAppDir := '..\'
  else if CanOpenFileRead('..\DOSST\VIEW.EXE') then
    TrackedRelAppDir := '..\DOSST\';

  if IOResult <> 0 then ;
  GetDir(0, StartupDir);
  if IOResult <> 0 then StartupDir := '';
  if (StartupDir <> '') and (StartupDir[Length(StartupDir)] <> '\') then
    StartupDir := StartupDir + '\';

  if CanOpenExe(StartupDir) then
  begin
    GetApplicationDir := StartupDir;
    Exit;
  end;

  if TryShortPath(StartupDir, ShortDir) and CanOpenExe(ShortDir) then
  begin
    GetApplicationDir := ShortDir;
    Exit;
  end;

  P := ParamStr(0);
  if (Length(P) >= 2) and (P[1] = '"') and (P[Length(P)] = '"') then
    P := Copy(P, 2, Length(P) - 2);
  I := Length(P);
  while (I > 0) and (P[I] <> '\') and (P[I] <> '/') and (P[I] <> ':') do
    Dec(I);

  if I > 0 then
  begin
    ParamDir := Copy(P, 1, I);
    if (ParamDir <> '') and (ParamDir[Length(ParamDir)] <> '\') then
      ParamDir := ParamDir + '\';
    if CanOpenExe(ParamDir) then
    begin
      GetApplicationDir := ParamDir;
      Exit;
    end;
    if TryShortPath(ParamDir, ShortDir) and CanOpenExe(ShortDir) then
    begin
      GetApplicationDir := ShortDir;
      Exit;
    end;
  end;

  if TryShortPath(StartupDir, ShortDir) then
    GetApplicationDir := ShortDir
  else
    GetApplicationDir := StartupDir;
end;

function ExportDiskAsZip(var ImgF: file; DataAreaStart: LongInt;
  BytesPerCluster: Word; RootDirStart: LongInt; RootDirSectors: Word;
  SectorsPerCluster: Byte; FatBuf: Pointer;
  const TargetZip: string; AutoDepack: Boolean): Boolean;
var
  ZipEntries: PZipWriteArray;
  TotalEntries: Integer;
  DirQueue: array[1..32] of record
    DirCluster: Word;
    PathPrefix: string[48];
  end;
  QHead, QTail: Integer;
  CurrentClust: Word;
  CurrentPrefix: string[48];
  SecIdx, EntryIdx: Integer;
  SectorBuf: array[0..511] of Byte;
  ClustOff, RootOff: LongInt;
  ActualRead: Word;
  DirFinished: Boolean;
  I: Integer;
  ZipF, TempF, SrcF: file;
  LFH: TZipLFH;
  CDH: TZipCDH;
  EOCD: TZipEOCD;
  CDOffset, CDSize: LongInt;
  Crc: LongInt;
  ReadLen: Word;
  BlockBuf: array[0..4095] of Byte;
  SrcToUse: string[16];
  DepName: string;
  DepSize: LongInt;
  SuccessDep: Boolean;
  NameStr: string[12];
  AttrByte: Byte;
  StartClustVal: Word;
  FileSizeVal: LongInt;
  TimeVal, DateVal: Word;
  ClustVal: Word;
  BytesLeft: LongInt;
  ToReadNow: Word;
begin
  ExportDiskAsZip := False;
  New(ZipEntries);
  TotalEntries := 0;

  QHead := 1;
  QTail := 1;
  DirQueue[1].DirCluster := 0;
  DirQueue[1].PathPrefix := '';

  while (QHead <= QTail) and (TotalEntries < 350) do
  begin
    CurrentClust := DirQueue[QHead].DirCluster;
    CurrentPrefix := DirQueue[QHead].PathPrefix;
    Inc(QHead);
    DirFinished := False;

    if CurrentClust = 0 then
    begin
      RootOff := RootDirStart;
      for SecIdx := 0 to RootDirSectors - 1 do
      begin
        if DirFinished then Break;
        Seek(ImgF, RootOff + (LongInt(SecIdx) * 512));
        if IOResult <> 0 then Break;
        BlockRead(ImgF, SectorBuf, 512, ActualRead);
        if ActualRead < 512 then Break;

        for EntryIdx := 0 to 15 do
        begin
          if SectorBuf[EntryIdx * 32] = 0 then
          begin
            DirFinished := True;
            Break;
          end;
          if (SectorBuf[EntryIdx * 32] <> $E5) and (SectorBuf[EntryIdx * 32 + 11] and $08 = 0) then
          begin
            NameStr := '';
            for I := 0 to 7 do
              if SectorBuf[EntryIdx * 32 + I] > 32 then NameStr := NameStr + Chr(SectorBuf[EntryIdx * 32 + I]);
            if SectorBuf[EntryIdx * 32 + 8] > 32 then
            begin
              NameStr := NameStr + '.';
              for I := 8 to 10 do
                if SectorBuf[EntryIdx * 32 + I] > 32 then NameStr := NameStr + Chr(SectorBuf[EntryIdx * 32 + I]);
            end;
            AttrByte := SectorBuf[EntryIdx * 32 + 11];
            TimeVal := (Word(SectorBuf[EntryIdx * 32 + 23]) shl 8) or SectorBuf[EntryIdx * 32 + 22];
            DateVal := (Word(SectorBuf[EntryIdx * 32 + 25]) shl 8) or SectorBuf[EntryIdx * 32 + 24];
            StartClustVal := (Word(SectorBuf[EntryIdx * 32 + 27]) shl 8) or SectorBuf[EntryIdx * 32 + 26];
            FileSizeVal := LongInt(SectorBuf[EntryIdx * 32 + 28]) or
                           (LongInt(SectorBuf[EntryIdx * 32 + 29]) shl 8) or
                           (LongInt(SectorBuf[EntryIdx * 32 + 30]) shl 16) or
                           (LongInt(SectorBuf[EntryIdx * 32 + 31]) shl 24);

            if (NameStr <> '.') and (NameStr <> '..') then
            begin
              if (AttrByte and $10 <> 0) then
              begin
                if QTail < 32 then
                begin
                  Inc(QTail);
                  DirQueue[QTail].DirCluster := StartClustVal;
                  DirQueue[QTail].PathPrefix := CurrentPrefix + NameStr + '/';
                end;
              end
              else
              begin
                if TotalEntries < 350 then
                begin
                  Inc(TotalEntries);
                  ZipEntries^[TotalEntries].RelPath := CurrentPrefix + NameStr;
                  ZipEntries^[TotalEntries].DosName := NameStr;
                  ZipEntries^[TotalEntries].StartCluster := StartClustVal;
                  ZipEntries^[TotalEntries].FileSize := FileSizeVal;
                  ZipEntries^[TotalEntries].Attr := AttrByte;
                  ZipEntries^[TotalEntries].TimeWord := TimeVal;
                  ZipEntries^[TotalEntries].DateWord := DateVal;
                end;
              end;
            end;
          end;
        end;
      end;
    end
    else
    begin
      ClustVal := CurrentClust;
      while (ClustVal >= 2) and (ClustVal < FAT12_EOC_MIN) and (not DirFinished) do
      begin
        ClustOff := DataAreaStart + (LongInt(ClustVal - 2) * BytesPerCluster);
        for SecIdx := 0 to SectorsPerCluster - 1 do
        begin
          if DirFinished then Break;
          Seek(ImgF, ClustOff + (LongInt(SecIdx) * 512));
          if IOResult <> 0 then Break;
          BlockRead(ImgF, SectorBuf, 512, ActualRead);
          if ActualRead < 512 then Break;

          for EntryIdx := 0 to 15 do
          begin
            if SectorBuf[EntryIdx * 32] = 0 then
            begin
              DirFinished := True;
              Break;
            end;
            if (SectorBuf[EntryIdx * 32] <> $E5) and (SectorBuf[EntryIdx * 32 + 11] and $08 = 0) then
            begin
              NameStr := '';
              for I := 0 to 7 do
                if SectorBuf[EntryIdx * 32 + I] > 32 then NameStr := NameStr + Chr(SectorBuf[EntryIdx * 32 + I]);
              if SectorBuf[EntryIdx * 32 + 8] > 32 then
              begin
                NameStr := NameStr + '.';
                for I := 8 to 10 do
                  if SectorBuf[EntryIdx * 32 + I] > 32 then NameStr := NameStr + Chr(SectorBuf[EntryIdx * 32 + I]);
              end;
              AttrByte := SectorBuf[EntryIdx * 32 + 11];
              TimeVal := (Word(SectorBuf[EntryIdx * 32 + 23]) shl 8) or SectorBuf[EntryIdx * 32 + 22];
              DateVal := (Word(SectorBuf[EntryIdx * 32 + 25]) shl 8) or SectorBuf[EntryIdx * 32 + 24];
              StartClustVal := (Word(SectorBuf[EntryIdx * 32 + 27]) shl 8) or SectorBuf[EntryIdx * 32 + 26];
              FileSizeVal := LongInt(SectorBuf[EntryIdx * 32 + 28]) or
                             (LongInt(SectorBuf[EntryIdx * 32 + 29]) shl 8) or
                             (LongInt(SectorBuf[EntryIdx * 32 + 30]) shl 16) or
                             (LongInt(SectorBuf[EntryIdx * 32 + 31]) shl 24);

              if (NameStr <> '.') and (NameStr <> '..') then
              begin
                if (AttrByte and $10 <> 0) then
                begin
                  if QTail < 32 then
                  begin
                    Inc(QTail);
                    DirQueue[QTail].DirCluster := StartClustVal;
                    DirQueue[QTail].PathPrefix := CurrentPrefix + NameStr + '/';
                  end;
                end
                else
                begin
                  if TotalEntries < 350 then
                  begin
                    Inc(TotalEntries);
                    ZipEntries^[TotalEntries].RelPath := CurrentPrefix + NameStr;
                    ZipEntries^[TotalEntries].DosName := NameStr;
                    ZipEntries^[TotalEntries].StartCluster := StartClustVal;
                    ZipEntries^[TotalEntries].FileSize := FileSizeVal;
                    ZipEntries^[TotalEntries].Attr := AttrByte;
                    ZipEntries^[TotalEntries].TimeWord := TimeVal;
                    ZipEntries^[TotalEntries].DateWord := DateVal;
                  end;
                end;
              end;
            end;
          end;
        end;
        ClustVal := GetFat12Entry(FatBuf, ClustVal);
      end;
    end;
  end;

  Assign(ZipF, TargetZip);
  Rewrite(ZipF, 1);
  if IOResult <> 0 then
  begin
    Dispose(ZipEntries);
    Exit;
  end;

  InitCRC32;

  for I := 1 to TotalEntries do
  begin
    ZipEntries^[I].LFHOffset := FilePos(ZipF);

    Assign(TempF, 'ZIP_TMP.$$$');
    Rewrite(TempF, 1);
    ClustVal := ZipEntries^[I].StartCluster;
    BytesLeft := ZipEntries^[I].FileSize;

    while (BytesLeft > 0) and (ClustVal >= 2) and (ClustVal < FAT12_EOC_MIN) do
    begin
      ClustOff := DataAreaStart + (LongInt(ClustVal - 2) * BytesPerCluster);
      ToReadNow := BytesPerCluster;
      if LongInt(ToReadNow) > BytesLeft then ToReadNow := Word(BytesLeft);
      Seek(ImgF, ClustOff);
      BlockRead(ImgF, BlockBuf, ToReadNow, ActualRead);
      BlockWrite(TempF, BlockBuf, ActualRead);
      Dec(BytesLeft, ActualRead);
      ClustVal := GetFat12Entry(FatBuf, ClustVal);
    end;
    Close(TempF);

    SrcToUse := 'ZIP_TMP.$$$';
    if AutoDepack then
    begin
      SuccessDep := DepackUniversal('ZIP_TMP.$$$', 'DEP_ZIP.$$$', DepName, DepSize);
      if SuccessDep and (DepSize > 0) then SrcToUse := 'DEP_ZIP.$$$';
    end;

    Assign(SrcF, SrcToUse);
    Reset(SrcF, 1);
    ZipEntries^[I].UncompSize := FileSize(SrcF);
    ZipEntries^[I].CompSize := ZipEntries^[I].UncompSize;

    Crc := $FFFFFFFF;
    while not Eof(SrcF) do
    begin
      BlockRead(SrcF, BlockBuf, SizeOf(BlockBuf), ReadLen);
      Crc := UpdateCRC32(Crc, BlockBuf, ReadLen);
    end;
    ZipEntries^[I].Crc32 := not Crc;

    LFH.Sig := $04034B50;
    LFH.VerNeeded := 20;
    LFH.Flags := 0;
    LFH.Method := 0;
    LFH.ModTime := ZipEntries^[I].TimeWord;
    LFH.ModDate := ZipEntries^[I].DateWord;
    LFH.CRC32 := ZipEntries^[I].Crc32;
    LFH.CompSize := ZipEntries^[I].CompSize;
    LFH.UncompSize := ZipEntries^[I].UncompSize;
    LFH.NameLen := Length(ZipEntries^[I].RelPath);
    LFH.ExtraLen := 0;

    BlockWrite(ZipF, LFH, SizeOf(LFH));
    BlockWrite(ZipF, ZipEntries^[I].RelPath[1], Length(ZipEntries^[I].RelPath));

    Reset(SrcF, 1);
    while not Eof(SrcF) do
    begin
      BlockRead(SrcF, BlockBuf, SizeOf(BlockBuf), ReadLen);
      BlockWrite(ZipF, BlockBuf, ReadLen);
    end;
    Close(SrcF);

    Assign(TempF, 'ZIP_TMP.$$$');
    Erase(TempF);
    if IOResult <> 0 then ;
    Assign(TempF, 'DEP_ZIP.$$$');
    Erase(TempF);
    if IOResult <> 0 then ;
  end;

  CDOffset := FilePos(ZipF);
  for I := 1 to TotalEntries do
  begin
    CDH.Sig := $02014B50;
    CDH.VerMadeBy := 20;
    CDH.VerNeeded := 20;
    CDH.Flags := 0;
    CDH.Method := 0;
    CDH.ModTime := ZipEntries^[I].TimeWord;
    CDH.ModDate := ZipEntries^[I].DateWord;
    CDH.CRC32 := ZipEntries^[I].Crc32;
    CDH.CompSize := ZipEntries^[I].CompSize;
    CDH.UncompSize := ZipEntries^[I].UncompSize;
    CDH.NameLen := Length(ZipEntries^[I].RelPath);
    CDH.ExtraLen := 0;
    CDH.CommentLen := 0;
    CDH.DiskStart := 0;
    CDH.IntAttr := 0;
    CDH.ExtAttr := LongInt(ZipEntries^[I].Attr);
    CDH.LocalHdrOffset := ZipEntries^[I].LFHOffset;

    BlockWrite(ZipF, CDH, SizeOf(CDH));
    BlockWrite(ZipF, ZipEntries^[I].RelPath[1], Length(ZipEntries^[I].RelPath));
  end;
  CDSize := FilePos(ZipF) - CDOffset;

  EOCD.Sig := $06054B50;
  EOCD.DiskNum := 0;
  EOCD.StartDisk := 0;
  EOCD.TotalEntriesDisk := TotalEntries;
  EOCD.TotalEntries := TotalEntries;
  EOCD.CDSize := CDSize;
  EOCD.CDOffset := CDOffset;
  EOCD.CommentLen := 0;

  BlockWrite(ZipF, EOCD, SizeOf(EOCD));
  Close(ZipF);
  Dispose(ZipEntries);
  ExportDiskAsZip := True;
end;

function AtariBootChecksum(Buf: Pointer): Word;
var
  Sum: LongInt;
  I: Integer;
  BA: PByteArray;
  W: Word;
begin
  Sum := 0;
  BA := Buf;
  for I := 0 to 255 do
  begin
    W := (Word(BA^[I * 2]) shl 8) or Word(BA^[I * 2 + 1]);
    Sum := (Sum + W) and $FFFF;
  end;
  AtariBootChecksum := Word(Sum);
end;

{ Scans buffer for ASCII substring }
function FindSig(Buf: Pointer; Len: Integer; const Sig: string): Boolean;
var
  BA: PByteArray;
  I, J, SigLen: Integer;
  Match: Boolean;
begin
  FindSig := False;
  SigLen := Length(Sig);
  if (Buf = nil) or (Len < SigLen) or (SigLen = 0) then Exit;
  BA := Buf;
  for I := 0 to Len - SigLen do
  begin
    Match := True;
    for J := 1 to SigLen do
    begin
      if Chr(BA^[I + J - 1]) <> Sig[J] then
      begin
        Match := False;
        Break;
      end;
    end;
    if Match then
    begin
      FindSig := True;
      Exit;
    end;
  end;
end;

{ Identifies Atari ST executable & data packers from first sector }
function DetectPacker(Buf: Pointer; Size: Integer): string;
var
  BA: PByteArray;
  Magic: Word;
begin
  DetectPacker := '';
  if (Buf = nil) or (Size < 4) then Exit;
  BA := Buf;
  Magic := ReadBE16(Buf, 0);

  { 1. GEMDOS Program Wrapper }
  if Magic = $601A then
  begin
    if FindSig(Buf, Size, 'Ice!') or FindSig(Buf, Size, 'ICE!') or FindSig(Buf, Size, 'Pack-Ice') then
      DetectPacker := 'Pack-Ice PRG'
    else if FindSig(Buf, Size, 'ATOM') or FindSig(Buf, Size, 'ATM5') or FindSig(Buf, Size, '/BMT') then
      DetectPacker := 'Atomik PRG'
    else if FindSig(Buf, Size, 'AU5!') or FindSig(Buf, Size, 'Automation') then
      DetectPacker := 'Automation'
    else if FindSig(Buf, Size, 'Pack-Fire') or FindSig(Buf, Size, 'Axe/Delight') then
      DetectPacker := 'Pack-Fire'
    else if FindSig(Buf, Size, 'FIRE') then
      DetectPacker := 'FIRE PRG'
    else if FindSig(Buf, Size, 'PP20') then
      DetectPacker := 'PowerPacker'
    else if FindSig(Buf, Size, 'POPI') or FindSig(Buf, Size, 'PUFF') then
      DetectPacker := 'Pompey PRG'
    else if FindSig(Buf, Size, 'Snt2') then
      DetectPacker := 'Sentry PRG'
    else if FindSig(Buf, Size, '4PAK') then
      DetectPacker := '4PAK PRG'
    else if FindSig(Buf, Size, 'RNC') then
      DetectPacker := 'RNC ProPack'
    else if FindSig(Buf, Size, 'HAPPY') or FindSig(Buf, Size, 'EASY') then
      DetectPacker := 'Happy Packer'
    else if FindSig(Buf, Size, 'JEK') or FindSig(Buf, Size, 'Byte Killer') then
      DetectPacker := 'JEK Packer'
    else if FindSig(Buf, Size, 'LZH!') then
      DetectPacker := 'JAM LZH PRG'
    else if FindSig(Buf, Size, 'JAM') then
      DetectPacker := 'JAM Packer'
    else
      DetectPacker := '';
    Exit;
  end;

  { 1b. Degas Elite Compressed Picture (.PC1, .PC2, .PC3) }
  if Magic = $8000 then begin DetectPacker := 'Degas Elite PC1'; Exit; end;
  if Magic = $8001 then begin DetectPacker := 'Degas Elite PC2'; Exit; end;
  if Magic = $8002 then begin DetectPacker := 'Degas Elite PC3'; Exit; end;

  { 1c. Titus Compressed Picture (.PC1) }
  if (Size >= 10) and ((BA^[0] = 1) or (BA^[0] = 2)) and (BA^[1] = 0) then
  begin
    DetectPacker := 'Titus PC1';
    Exit;
  end;

  { 2. Raw Compressed Data Signatures }
  if (Chr(BA^[0]) = 'I') and (Chr(BA^[1]) = 'c') and (Chr(BA^[2]) = 'e') and (Chr(BA^[3]) = '!') then
    DetectPacker := 'Pack-Ice'
  else if (Chr(BA^[0]) = 'I') and (Chr(BA^[1]) = 'C') and (Chr(BA^[2]) = 'E') and (Chr(BA^[3]) = '!') then
    DetectPacker := 'Pack-Ice v2.4'
  else if (Chr(BA^[0]) = 'A') and (Chr(BA^[1]) = 'T') and (Chr(BA^[2]) = 'M') then
    DetectPacker := 'Atomik Data'
  else if (Chr(BA^[0]) = 'A') and (Chr(BA^[1]) = 'T') and (Chr(BA^[2]) = 'O') and (Chr(BA^[3]) = 'M') then
    DetectPacker := 'Thunder Raw'
  else if (Chr(BA^[0]) = 'R') and (Chr(BA^[1]) = 'N') and (Chr(BA^[2]) = 'C') then
    DetectPacker := 'RNC Data'
  else if (Chr(BA^[0]) = 'F') and (Chr(BA^[1]) = 'I') and (Chr(BA^[2]) = 'R') and (Chr(BA^[3]) = 'E') then
    DetectPacker := 'FIRE Data'
  else if (Chr(BA^[0]) = 'P') and (Chr(BA^[1]) = 'P') and (Chr(BA^[2]) = '2') and (Chr(BA^[3]) = '0') then
    DetectPacker := 'PowerPacker'
  else if (Chr(BA^[0]) = 'L') and (Chr(BA^[1]) = 'S') and (Chr(BA^[2]) = 'D') and (Chr(BA^[3]) = '!') then
    DetectPacker := 'Automation'
  else if (Chr(BA^[0]) = 'A') and (Chr(BA^[1]) = 'U') and (Chr(BA^[2]) = '5') and (Chr(BA^[3]) = '!') then
    DetectPacker := 'Automation v5'
  else if (Chr(BA^[0]) = 'J') and (Chr(BA^[1]) = 'A') and (Chr(BA^[2]) = 'M') then
    DetectPacker := 'JAM Packer'
  else if (Chr(BA^[0]) = 'J') and (Chr(BA^[1]) = 'E') and (Chr(BA^[2]) = 'K') and (Chr(BA^[3]) = '!') then
    DetectPacker := 'JEK Data'
  else if (Chr(BA^[0]) = 'L') and (Chr(BA^[1]) = 'Z') and (Chr(BA^[2]) = 'H') and (Chr(BA^[3]) = '!') then
    DetectPacker := 'JAM LZH Data'
  else if (Chr(BA^[0]) = 'C') and (Chr(BA^[1]) = 'r') and (Chr(BA^[2]) = 'M') then
    DetectPacker := 'Crunch-Mania'
  else if (Chr(BA^[0]) = 'p') and (Chr(BA^[1]) = 'M') and (Chr(BA^[2]) = '8') and
          ((Chr(BA^[3]) = '5') or (Chr(BA^[3]) = '6')) then
    DetectPacker := 'STAD Image'
  else if (Chr(BA^[0]) = 'S') and (Chr(BA^[1]) = 'P') and (Chr(BA^[2]) = '2') and (Chr(BA^[3]) = '0') then
    DetectPacker := 'Speedpacker';
end;


function BiosDiskReset(Drive: Byte): Byte;
var
  Regs: Registers;
begin
  Regs.AH := $00;
  Regs.DL := Drive;
  Intr($13, Regs);
  BiosDiskReset := Regs.AH;
end;

function BiosWriteSectors(Drive, Head, Track, Sector, Count: Byte; var Buffer): Byte;
var
  Regs: Registers;
begin
  Regs.AH := $03;
  Regs.AL := Count;
  Regs.CH := Track;
  Regs.CL := Sector;
  Regs.DH := Head;
  Regs.DL := Drive;
  Regs.ES := Seg(Buffer);
  Regs.BX := Ofs(Buffer);
  Intr($13, Regs);
  if (Regs.Flags and 1) <> 0 then
    BiosWriteSectors := Regs.AH
  else
    BiosWriteSectors := 0;
end;

function BiosReadSectors(Drive, Head, Track, Sector, Count: Byte; var Buffer): Byte;
var
  Regs: Registers;
begin
  Regs.AH := $02;
  Regs.AL := Count;
  Regs.CH := Track;
  Regs.CL := Sector;
  Regs.DH := Head;
  Regs.DL := Drive;
  Regs.ES := Seg(Buffer);
  Regs.BX := Ofs(Buffer);
  Intr($13, Regs);
  if (Regs.Flags and 1) <> 0 then
    BiosReadSectors := Regs.AH
  else
    BiosReadSectors := 0;
end;

{ Returns BIOS drive type (1=360K,2=1.2M,3=720K,4=1.44M,5=2.88M) or 0 if unknown }
function BiosDriveType(Drive: Byte): Byte;
var
  Regs: Registers;
begin
  Regs.AH := $08;
  Regs.DL := Drive;
  Intr($13, Regs);
  if ((Regs.Flags and 1) <> 0) or (Regs.AH <> 0) then
    BiosDriveType := 0
  else
    BiosDriveType := Regs.BL;
end;

function BiosDiskErrorStr(Code: Byte): string;
begin
  case Code of
    $00: BiosDiskErrorStr := 'Success';
    $01: BiosDiskErrorStr := 'Invalid command';
    $02: BiosDiskErrorStr := 'Address mark not found';
    $03: BiosDiskErrorStr := 'Disk is WRITE-PROTECTED';
    $04: BiosDiskErrorStr := 'Sector not found';
    $06: BiosDiskErrorStr := 'Floppy disk changed';
    $08: BiosDiskErrorStr := 'DMA overrun';
    $09: BiosDiskErrorStr := 'DMA boundary crossed';
    $0C: BiosDiskErrorStr := 'Media type not found';
    $10: BiosDiskErrorStr := 'CRC / Data error';
    $20: BiosDiskErrorStr := 'Controller failure';
    $40: BiosDiskErrorStr := 'Seek operation failed';
    $80: BiosDiskErrorStr := 'Drive timed out / Not ready';
    else BiosDiskErrorStr := 'Error $' + HexStrByte(Code);
  end;
end;

var
  FloppyRawMem: Pointer;

const
  FLOPPY_BUF_SIZE = 18 * 512;

{ Allocates a track buffer aligned so it never crosses a 64K DMA boundary }
function FloppyBufAlloc: Pointer;
var
  Lin: LongInt;
begin
  FloppyBufAlloc := nil;
  if FloppyRawMem <> nil then Exit;
  if MaxAvail < 2 * LongInt(FLOPPY_BUF_SIZE) + 1024 then Exit;
  GetMem(FloppyRawMem, 2 * FLOPPY_BUF_SIZE);
  Lin := LongInt(Seg(FloppyRawMem^)) * 16 + Ofs(FloppyRawMem^);
  if (Lin and $FFFF) + FLOPPY_BUF_SIZE > $10000 then
    Lin := Lin + ($10000 - (Lin and $FFFF));
  FloppyBufAlloc := Ptr(Lin shr 4, Lin and 15);
end;

procedure FloppyBufFree;
begin
  if FloppyRawMem <> nil then
  begin
    FreeMem(FloppyRawMem, 2 * FLOPPY_BUF_SIZE);
    FloppyRawMem := nil;
  end;
end;

{ Reads boot sector and derives geometry from BPB, falling back to BIOS drive type }
function FloppyDetectGeometry(Drive: Byte; Buf: Pointer; var Sides, SPT, Tracks, TotalSec: Word;
  var Status: Byte): Boolean;
var
  B: PByteArray;
  Retry: Integer;
  BytesPS: Word;
  Got: Boolean;
begin
  FloppyDetectGeometry := False;
  BiosDiskReset(Drive);
  Got := False;
  Status := 0;
  for Retry := 1 to 4 do
  begin
    Status := BiosReadSectors(Drive, 0, 0, 1, 1, Buf^);
    if Status = 0 then begin Got := True; Break; end;
    BiosDiskReset(Drive);
  end;
  if not Got then Exit;
  B := PByteArray(Buf);
  BytesPS  := B^[11] + B^[12] * 256;
  TotalSec := B^[19] + B^[20] * 256;
  SPT      := B^[24] + B^[25] * 256;
  Sides    := B^[26] + B^[27] * 256;
  if (BytesPS <> 512) or (SPT < 8) or (SPT > 18) or (Sides < 1) or (Sides > 2) or
     (TotalSec < Word(40 * SPT)) or (TotalSec > Word(84 * SPT * Sides)) then
  begin
    case BiosDriveType(Drive) of
      1: begin Sides := 2; SPT := 9;  TotalSec := 720;  end;
      2: begin Sides := 2; SPT := 15; TotalSec := 2400; end;
      4: begin Sides := 2; SPT := 18; TotalSec := 2880; end;
    else
      Sides := 2; SPT := 9; TotalSec := 1440;
    end;
  end;
  Tracks := TotalSec div (Sides * SPT);
  if Tracks = 0 then Tracks := 80;
  TotalSec := Tracks * Sides * SPT;
  FloppyDetectGeometry := True;
end;

{ Reads one track into Buf; unreadable sectors are zero-filled. Returns bad sector count }
function FloppyReadTrack(Drive: Byte; Head, Cyl, SPT: Word; Buf: Pointer): Word;
var
  Retry, Sec: Integer;
  Status: Byte;
  Ok: Boolean;
  Bad: Word;
  P: Pointer;
begin
  Bad := 0;
  Ok := False;
  for Retry := 1 to 3 do
  begin
    Status := BiosReadSectors(Drive, Head, Cyl, 1, SPT, Buf^);
    if Status = 0 then begin Ok := True; Break; end;
    BiosDiskReset(Drive);
  end;
  if not Ok then
    for Sec := 1 to SPT do
    begin
      P := Ptr(Seg(Buf^), Ofs(Buf^) + (Sec - 1) * 512);
      Ok := False;
      for Retry := 1 to 3 do
      begin
        Status := BiosReadSectors(Drive, Head, Cyl, Sec, 1, P^);
        if Status = 0 then begin Ok := True; Break; end;
        BiosDiskReset(Drive);
      end;
      if not Ok then
      begin
        FillChar(P^, 512, 0);
        Inc(Bad);
      end;
    end;
  FloppyReadTrack := Bad;
end;

procedure EraseFileQuiet(const P: string);
var
  F: file;
begin
  Assign(F, P);
  Erase(F);
  if IOResult <> 0 then ;
end;

function CopyFileTo(const Src, Dst: string): Boolean;
var
  F1, F2: file;
  Chunk: Pointer;
  NR, NW: Word;
  Ok: Boolean;
begin
  CopyFileTo := False;
  if MaxAvail < 4096 then Exit;
  GetMem(Chunk, 4096);
  Assign(F1, Src);
  Reset(F1, 1);
  if IOResult = 0 then
  begin
    Assign(F2, Dst);
    Rewrite(F2, 1);
    if IOResult = 0 then
    begin
      Ok := True;
      repeat
        BlockRead(F1, Chunk^, 4096, NR);
        if NR > 0 then
        begin
          BlockWrite(F2, Chunk^, NR, NW);
          if (IOResult <> 0) or (NW <> NR) then Ok := False;
        end;
      until (NR = 0) or (not Ok);
      Close(F2);
      if IOResult <> 0 then Ok := False;
      CopyFileTo := Ok;
    end;
    Close(F1);
    if IOResult <> 0 then ;
  end;
  FreeMem(Chunk, 4096);
end;



procedure InitCRC32;
var
  I, J: Integer;
  C: LongInt;
begin
  if CrcTableReady then Exit;
  for I := 0 to 255 do
  begin
    C := I;
    for J := 0 to 7 do
    begin
      if (C and 1) <> 0 then
        C := (C shr 1) xor (-306674912)
      else
        C := C shr 1;
    end;
    CrcTable[I] := C;
  end;
  CrcTableReady := True;
end;

function UpdateCRC32(Crc: LongInt; const Buf; Len: Word): LongInt;
var
  BA: array[0..65520] of Byte absolute Buf;
  I: Word;
begin
  for I := 0 to Len - 1 do
    Crc := CrcTable[(Crc xor Byte(BA[I])) and $FF] xor ((Crc shr 8) and $00FFFFFF);
  UpdateCRC32 := Crc;
end;


function UnpackMSAToFile(const MSAFileName, OutSTFileName: string): Boolean;
var
  MSAF, STF: file;
  Hdr: array[0..9] of Byte;
  SecPerTrack, SidesCount, StartTrack, EndTrack: Word;
  TrackSize, ExpectedTotalTracks, ExpectedTotalBytes: LongInt;
  Trk, Side: Integer;
  TrackLenBE: array[0..1] of Byte;
  TrackLen: Word;
  InTrackBuf, OutTrackBuf: PBigByteArray;
  InPos, OutPos: Word;
  ActualRead: Word;
  B, DataByte: Byte;
  Count: Word;
  PadBytes: LongInt;
  AnyWritten: Boolean;
begin
  UnpackMSAToFile := False;
  Assign(MSAF, MSAFileName);
  Reset(MSAF, 1);
  if IOResult <> 0 then Exit;

  if FileSize(MSAF) < 10 then
  begin
    Close(MSAF);
    Exit;
  end;

  BlockRead(MSAF, Hdr, 10, ActualRead);
  if (Hdr[0] <> $0E) or (Hdr[1] <> $0F) then
  begin
    Close(MSAF);
    Exit;
  end;

  SecPerTrack := (Word(Hdr[2]) shl 8) or Hdr[3];
  SidesCount := ((Word(Hdr[4]) shl 8) or Hdr[5]) + 1;
  StartTrack := (Word(Hdr[6]) shl 8) or Hdr[7];
  EndTrack := (Word(Hdr[8]) shl 8) or Hdr[9];

  if (SecPerTrack < 1) or (SecPerTrack > 36) then SecPerTrack := 9;
  if (SidesCount < 1) or (SidesCount > 2) then SidesCount := 2;
  if (EndTrack < StartTrack) or (EndTrack > 90) then EndTrack := 79;

  TrackSize := LongInt(SecPerTrack) * 512;
  ExpectedTotalTracks := LongInt(EndTrack - StartTrack + 1);
  ExpectedTotalBytes := ExpectedTotalTracks * LongInt(SidesCount) * TrackSize;

  Assign(STF, OutSTFileName);
  Rewrite(STF, 1);
  if IOResult <> 0 then
  begin
    Close(MSAF);
    Exit;
  end;

  GetMem(InTrackBuf, 16384);
  GetMem(OutTrackBuf, 16384);
  AnyWritten := False;

  for Trk := StartTrack to EndTrack do
  begin
    for Side := 0 to SidesCount - 1 do
    begin
      if FilePos(MSAF) + 2 > FileSize(MSAF) then Break;
      BlockRead(MSAF, TrackLenBE, 2, ActualRead);
      if ActualRead < 2 then Break;
      TrackLen := (Word(TrackLenBE[0]) shl 8) or TrackLenBE[1];

      if TrackLen = Word(TrackSize) then
      begin
        { Uncompressed track }
        BlockRead(MSAF, OutTrackBuf^[0], Word(TrackSize), ActualRead);
        if ActualRead < Word(TrackSize) then
          FillChar(OutTrackBuf^[ActualRead], Word(TrackSize) - ActualRead, 0);
        BlockWrite(STF, OutTrackBuf^[0], Word(TrackSize));
        AnyWritten := True;
      end
      else
      begin
        { RLE compressed track }
        if TrackLen > 16384 then TrackLen := 16384;
        BlockRead(MSAF, InTrackBuf^[0], TrackLen, ActualRead);
        FillChar(OutTrackBuf^[0], Word(TrackSize), 0);
        InPos := 0;
        OutPos := 0;

        while (InPos < ActualRead) and (OutPos < Word(TrackSize)) do
        begin
          B := InTrackBuf^[InPos];
          Inc(InPos);
          if B = $E5 then
          begin
            if InPos >= ActualRead then Break;
            DataByte := InTrackBuf^[InPos];
            Inc(InPos);
            if InPos + 1 >= ActualRead then Break;
            Count := (Word(InTrackBuf^[InPos]) shl 8) or InTrackBuf^[InPos + 1];
            Inc(InPos, 2);

            if OutPos + Count > Word(TrackSize) then
              Count := Word(TrackSize) - OutPos;

            if Count > 0 then
            begin
              FillChar(OutTrackBuf^[OutPos], Count, DataByte);
              Inc(OutPos, Count);
            end;
          end
          else
          begin
            OutTrackBuf^[OutPos] := B;
            Inc(OutPos);
          end;
        end;

        BlockWrite(STF, OutTrackBuf^[0], Word(TrackSize));
        AnyWritten := True;
      end;
    end;
    if FilePos(MSAF) >= FileSize(MSAF) then Break;
  end;

  { If file ended early, pad out to expected disk geometry }
  if (FileSize(STF) > 0) and (FileSize(STF) < ExpectedTotalBytes) then
  begin
    FillChar(OutTrackBuf^[0], Word(TrackSize), 0);
    while FileSize(STF) < ExpectedTotalBytes do
    begin
      PadBytes := ExpectedTotalBytes - FileSize(STF);
      if PadBytes > TrackSize then PadBytes := TrackSize;
      BlockWrite(STF, OutTrackBuf^[0], Word(PadBytes));
    end;
  end;

  FreeMem(OutTrackBuf, 16384);
  FreeMem(InTrackBuf, 16384);
  Close(MSAF);
  Close(STF);

  UnpackMSAToFile := AnyWritten;
end;



function IsDIMFile(const Path: string): Boolean;
var
  F: file;
  Hdr: TDIMHeader;
  Ext: string[4];
  I: Integer;
  ActualRead: Word;
  FSize: LongInt;
begin
  IsDIMFile := False;
  if IOResult <> 0 then ;
  Ext := '';
  if Length(Path) >= 4 then
    Ext := Copy(Path, Length(Path) - 3, 4);
  for I := 1 to Length(Ext) do Ext[I] := UpCase(Ext[I]);

  Assign(F, Path);
  Reset(F, 1);
  if IOResult <> 0 then Exit;

  FSize := FileSize(F);
  if FSize < 32 + 512 then
  begin
    Close(F);
    if IOResult <> 0 then ;
    Exit;
  end;

  BlockRead(F, Hdr, 32, ActualRead);
  Close(F);
  if IOResult <> 0 then ;

  if (ActualRead = 32) and (Hdr.ID = DIM_MAGIC) then
    IsDIMFile := True
  else if (Ext = '.DIM') and (FSize >= 368640) and ((FSize mod 512) = 32) and
          (Hdr.ID <> $6152) and (Hdr.ID <> $4B50) then
    IsDIMFile := True;
end;

function UnpackDIMToFile(const DimFileName, OutSTFileName: string): Boolean;
var
  InF, OutF: file;
  Hdr: TDIMHeader;
  ActualRead, ActualWrite: Word;
  Buf: array[0..4095] of Byte;
  ZeroSec: array[0..511] of Byte;
  SecBuf: array[0..511] of Byte;
  TotalToCopy, InSize: LongInt;
  ToRead: Word;
  SidesCount, Spt, Tracks, TotalSec: Integer;
  BitmapBytes: Integer;
  Bitmap: array[0..2047] of Byte;
  SecIdx, ByteIdx, BitIdx: Integer;
  IsMarked, LsbFirst: Boolean;
begin
  UnpackDIMToFile := False;
  if IOResult <> 0 then ;
  Assign(InF, DimFileName);
  Reset(InF, 1);
  if IOResult <> 0 then Exit;

  InSize := FileSize(InF);
  if InSize < 32 + 512 then
  begin
    Close(InF);
    if IOResult <> 0 then ;
    Exit;
  end;

  BlockRead(InF, Hdr, 32, ActualRead);
  if (ActualRead < 32) or (Hdr.ID = $6152) or (Hdr.ID = $4B50) then
  begin
    Close(InF);
    if IOResult <> 0 then ;
    Exit;
  end;
  if (Hdr.ID <> DIM_MAGIC) and ((InSize mod 512) <> 32) then
  begin
    Close(InF);
    if IOResult <> 0 then ;
    Exit;
  end;

  Assign(OutF, OutSTFileName);
  Erase(OutF);
  if IOResult <> 0 then ;
  Assign(OutF, OutSTFileName);
  Rewrite(OutF, 1);
  if IOResult <> 0 then
  begin
    Close(InF);
    if IOResult <> 0 then ;
    Exit;
  end;

  if (Hdr.ID = DIM_MAGIC) and (Hdr.SectorMode = 1) then
  begin
    SidesCount := Hdr.Sides + 1;
    if (SidesCount < 1) or (SidesCount > 2) then SidesCount := 2;
    Spt := Hdr.SectorsPerTrack;
    if (Spt < 8) or (Spt > 24) then Spt := 9;
    Tracks := (Hdr.EndTrack - Hdr.StartTrack) + 1;
    if (Tracks < 1) or (Tracks > 90) then Tracks := 80;
    TotalSec := Tracks * SidesCount * Spt;
    BitmapBytes := (TotalSec + 7) div 8;

    FillChar(ZeroSec, SizeOf(ZeroSec), 0);
    FillChar(Bitmap, SizeOf(Bitmap), 0);
    if BitmapBytes > SizeOf(Bitmap) then BitmapBytes := SizeOf(Bitmap);

    BlockRead(InF, Bitmap, BitmapBytes, ActualRead);

    if ((Bitmap[0] and $01) <> 0) and ((Bitmap[0] and $80) = 0) then
      LsbFirst := True
    else
      LsbFirst := False;

    for SecIdx := 0 to TotalSec - 1 do
    begin
      ByteIdx := SecIdx div 8;
      BitIdx := SecIdx mod 8;
      if ByteIdx < BitmapBytes then
      begin
        if LsbFirst then
          IsMarked := (Bitmap[ByteIdx] and (1 shl BitIdx)) <> 0
        else
          IsMarked := (Bitmap[ByteIdx] and ($80 shr BitIdx)) <> 0;
      end
      else
        IsMarked := False;

      if IsMarked then
      begin
        BlockRead(InF, SecBuf, 512, ActualRead);
        if ActualRead = 512 then
          BlockWrite(OutF, SecBuf, 512, ActualWrite)
        else
        begin
          if ActualRead > 0 then BlockWrite(OutF, SecBuf, ActualRead, ActualWrite);
          if ActualRead < 512 then BlockWrite(OutF, ZeroSec, 512 - ActualRead, ActualWrite);
        end;
      end
      else
      begin
        BlockWrite(OutF, ZeroSec, 512, ActualWrite);
      end;
    end;
  end
  else
  begin
    Seek(InF, 32);
    TotalToCopy := FileSize(InF) - 32;
    while TotalToCopy > 0 do
    begin
      if TotalToCopy > SizeOf(Buf) then ToRead := SizeOf(Buf) else ToRead := Word(TotalToCopy);
      BlockRead(InF, Buf, ToRead, ActualRead);
      if ActualRead = 0 then Break;
      BlockWrite(OutF, Buf, ActualRead, ActualWrite);
      Dec(TotalToCopy, ActualRead);
    end;
  end;

  Close(InF);
  Close(OutF);
  UnpackDIMToFile := True;
end;

function WildcardMatch(Pattern, Target: string): Boolean;
var
  PIdx, TIdx: Integer;
  PCh: Char;
  P, T: string;
  I: Integer;
begin
  P := Pattern;
  T := Target;
  for I := 1 to Length(P) do P[I] := UpCase(P[I]);
  for I := 1 to Length(T) do T[I] := UpCase(T[I]);

  if (P = '*.*') or (P = '*') or (P = '') then
  begin
    WildcardMatch := True;
    Exit;
  end;

  PIdx := 1;
  TIdx := 1;
  while (PIdx <= Length(P)) and (TIdx <= Length(T)) do
  begin
    PCh := P[PIdx];
    if PCh = '*' then
    begin
      Inc(PIdx);
      if PIdx > Length(P) then
      begin
        WildcardMatch := True;
        Exit;
      end;
      while TIdx <= Length(T) do
      begin
        if WildcardMatch(Copy(P, PIdx, Length(P) - PIdx + 1), Copy(T, TIdx, Length(T) - TIdx + 1)) then
        begin
          WildcardMatch := True;
          Exit;
        end;
        Inc(TIdx);
      end;
      WildcardMatch := False;
      Exit;
    end
    else if (PCh = '?') or (PCh = T[TIdx]) then
    begin
      Inc(PIdx);
      Inc(TIdx);
    end
    else
    begin
      WildcardMatch := False;
      Exit;
    end;
  end;

  while (PIdx <= Length(P)) and (P[PIdx] = '*') do Inc(PIdx);
  WildcardMatch := (PIdx > Length(P)) and (TIdx > Length(T));
end;

function FormatFileSize(Bytes: LongInt): string;
var
  S, Res: string[16];
  I, Count: Integer;
begin
  Str(Bytes, S);
  Res := '';
  Count := 0;
  for I := Length(S) downto 1 do
  begin
    if (Count > 0) and (Count mod 3 = 0) then
      Res := ',' + Res;
    Res := S[I] + Res;
    Inc(Count);
  end;
  FormatFileSize := Res;
end;

function FormatAttr(Attr: Byte): string;
var
  S: string[6];
begin
  S := '----';
  if (Attr and $10) <> 0 then S[1] := 'D' else if (Attr and $01) <> 0 then S[1] := 'R';
  if (Attr and $02) <> 0 then S[2] := 'H';
  if (Attr and $04) <> 0 then S[3] := 'S';
  if (Attr and $20) <> 0 then S[4] := 'A';
  FormatAttr := S;
end;

function SanitizeTo83(const InputName: string; var Name8, Ext3: string): Boolean;
var
  Clean: string[30];
  I, DotPos: Integer;
  Ch: Char;
begin
  SanitizeTo83 := False;
  Name8 := '';
  Ext3 := '';
  Clean := '';

  for I := 1 to Length(InputName) do
  begin
    Ch := UpCase(InputName[I]);
    if Ch in ['A'..'Z', '0'..'9', '_', '-', '~', '!', '@', '#', '$', '%', '&', '(', ')', '.'] then
      Clean := Clean + Ch;
  end;

  if Clean = '' then Exit;

  DotPos := 0;
  for I := Length(Clean) downto 1 do
  begin
    if Clean[I] = '.' then
    begin
      DotPos := I;
      Break;
    end;
  end;

  if DotPos > 0 then
  begin
    Name8 := Copy(Clean, 1, DotPos - 1);
    Ext3 := Copy(Clean, DotPos + 1, 3);
  end
  else
  begin
    Name8 := Clean;
    Ext3 := '';
  end;

  if Length(Name8) > 8 then Name8 := Copy(Name8, 1, 8);
  if Length(Ext3) > 3 then Ext3 := Copy(Ext3, 1, 3);

  SanitizeTo83 := (Length(Name8) > 0);
end;

procedure GetCurrentDosTimeDate(var FTime, FDate: Word);
var
  Y, M, D, DOW: Word;
  H, Min, Sec, S100: Word;
begin
  GetDate(Y, M, D, DOW);
  GetTime(H, Min, Sec, S100);

  if Y < 1980 then Y := 1980;
  FDate := ((Y - 1980) shl 9) or (M shl 5) or D;
  FTime := (H shl 11) or (Min shl 5) or (Sec shr 1);
end;

function GetFat12Entry(FatBuf: PByteArray; Cluster: Word): Word;
var
  Off: Word;
  V: Word;
begin
  if Cluster < 2 then
  begin
    GetFat12Entry := FAT12_EOC;
    Exit;
  end;
  Off := (Cluster * 3) div 2;
  V := Word(FatBuf^[Off]) or (Word(FatBuf^[Off + 1]) shl 8);
  if (Cluster and 1) = 0 then
    GetFat12Entry := V and $0FFF
  else
    GetFat12Entry := V shr 4;
end;

procedure SetFat12Entry(FatBuf: PByteArray; Cluster, Value: Word);
var
  Off: Word;
  OldV, NewV: Word;
begin
  if Cluster < 2 then Exit;
  Off := (Cluster * 3) div 2;
  OldV := Word(FatBuf^[Off]) or (Word(FatBuf^[Off + 1]) shl 8);
  if (Cluster and 1) = 0 then
    NewV := (OldV and $F000) or (Value and $0FFF)
  else
    NewV := (OldV and $000F) or (Value shl 4);
  FatBuf^[Off] := Byte(NewV and $FF);
  FatBuf^[Off + 1] := Byte((NewV shr 8) and $FF);
end;

function ExtractDirEntryName(EntryPtr: PByteArray): string;
var
  N, E: string[12];
  I: Integer;
begin
  N := ''; E := '';
  for I := 0 to 7 do
    if (EntryPtr^[I] >= 33) and (EntryPtr^[I] <= 126) then
      N := N + Chr(EntryPtr^[I]);
  for I := 8 to 10 do
    if (EntryPtr^[I] >= 33) and (EntryPtr^[I] <= 126) then
      E := E + Chr(EntryPtr^[I]);
  if E <> '' then
    ExtractDirEntryName := N + '.' + E
  else
    ExtractDirEntryName := N;
end;

function SearchDiskRecursive(var ImgF: file; DataAreaStart: LongInt;
  BytesPerCluster: Word; RootDirStart: LongInt; RootDirSectors: Word;
  SectorsPerCluster: Byte; FatBuf: Pointer; const Pattern: string;
  var Results: array of TSearchRecord; MaxResults: Integer): Integer;
var
  DirQueue: array[1..64] of record
    Clust: Word;
    Path: string[36];
  end;
  QHead, QTail: Integer;
  CurClust: Word;
  CurPath: string[36];
  SectorBuf: array[0..511] of Byte;
  SecIdx, EntryIdx: Integer;
  CurrentOff: LongInt;
  ActualRead: Word;
  Attr: Byte;
  StartClust: Word;
  FileSizeVal: LongInt;
  CleanName: string[12];
  MatchCount: Integer;
  FatDate, FatTime: Word;
begin
  MatchCount := 0;
  QHead := 1;
  QTail := 1;
  DirQueue[1].Clust := 0;
  DirQueue[1].Path := '\';

  while (QHead <= QTail) and (MatchCount < MaxResults) do
  begin
    CurClust := DirQueue[QHead].Clust;
    CurPath := DirQueue[QHead].Path;
    Inc(QHead);

    if CurClust = 0 then
    begin
      { Root directory scan }
      CurrentOff := RootDirStart;
      for SecIdx := 0 to RootDirSectors - 1 do
      begin
        Seek(ImgF, CurrentOff);
        if IOResult <> 0 then Break;
        BlockRead(ImgF, SectorBuf, 512, ActualRead);
        if ActualRead < 512 then Break;

        for EntryIdx := 0 to 15 do
        begin
          if SectorBuf[EntryIdx * 32] = $00 then Break;
          if SectorBuf[EntryIdx * 32] <> $E5 then
          begin
            Attr := SectorBuf[EntryIdx * 32 + 11];
            if (Attr and $08) = 0 then { Not volume label }
            begin
              CleanName := ExtractDirEntryName(@SectorBuf[EntryIdx * 32]);
              StartClust := Word(SectorBuf[EntryIdx * 32 + 26]) or (Word(SectorBuf[EntryIdx * 32 + 27]) shl 8);
              FileSizeVal := LongInt(SectorBuf[EntryIdx * 32 + 28]) or
                             (LongInt(SectorBuf[EntryIdx * 32 + 29]) shl 8) or
                             (LongInt(SectorBuf[EntryIdx * 32 + 30]) shl 16) or
                             (LongInt(SectorBuf[EntryIdx * 32 + 31]) shl 24);
              FatTime := Word(SectorBuf[EntryIdx * 32 + 22]) or (Word(SectorBuf[EntryIdx * 32 + 23]) shl 8);
              FatDate := Word(SectorBuf[EntryIdx * 32 + 24]) or (Word(SectorBuf[EntryIdx * 32 + 25]) shl 8);

              if (Attr and $10) <> 0 then
              begin
                { Subdirectory }
                if (CleanName <> '.') and (CleanName <> '..') and (QTail < 64) then
                begin
                  Inc(QTail);
                  DirQueue[QTail].Clust := StartClust;
                  DirQueue[QTail].Path := CurPath + CleanName + '\';
                end;
              end;

              if (CleanName <> '.') and (CleanName <> '..') and WildcardMatch(Pattern, CleanName) then
              begin
                if MatchCount < MaxResults then
                begin
                  Inc(MatchCount);
                  Results[MatchCount - 1].DirPath := CurPath;
                  Results[MatchCount - 1].Name := CleanName;
                  Results[MatchCount - 1].Size := FileSizeVal;
                  Results[MatchCount - 1].Attr := Attr;
                  Results[MatchCount - 1].StartCluster := StartClust;
                  Results[MatchCount - 1].ParentCluster := 0;
                  Results[MatchCount - 1].IsDir := (Attr and $10) <> 0;
                  Results[MatchCount - 1].Year := 1980 + (FatDate shr 9);
                  Results[MatchCount - 1].Month := (FatDate shr 5) and 15;
                  Results[MatchCount - 1].Day := FatDate and 31;
                  Results[MatchCount - 1].Hour := FatTime shr 11;
                  Results[MatchCount - 1].Min := (FatTime shr 5) and 63;
                end;
              end;
            end;
          end;
        end;
        CurrentOff := CurrentOff + 512;
      end;
    end
    else
    begin
      { Subdirectory cluster scan }
      while (CurClust >= 2) and (CurClust < FAT12_EOC_MIN) do
      begin
        CurrentOff := DataAreaStart + LongInt(CurClust - 2) * BytesPerCluster;
        for SecIdx := 0 to SectorsPerCluster - 1 do
        begin
          Seek(ImgF, CurrentOff);
          if IOResult <> 0 then Break;
          BlockRead(ImgF, SectorBuf, 512, ActualRead);
          if ActualRead < 512 then Break;

          for EntryIdx := 0 to 15 do
          begin
            if SectorBuf[EntryIdx * 32] = $00 then Break;
            if SectorBuf[EntryIdx * 32] <> $E5 then
            begin
              Attr := SectorBuf[EntryIdx * 32 + 11];
              if (Attr and $08) = 0 then
              begin
                CleanName := ExtractDirEntryName(@SectorBuf[EntryIdx * 32]);
                StartClust := Word(SectorBuf[EntryIdx * 32 + 26]) or (Word(SectorBuf[EntryIdx * 32 + 27]) shl 8);
                FileSizeVal := LongInt(SectorBuf[EntryIdx * 32 + 28]) or
                               (LongInt(SectorBuf[EntryIdx * 32 + 29]) shl 8) or
                               (LongInt(SectorBuf[EntryIdx * 32 + 30]) shl 16) or
                               (LongInt(SectorBuf[EntryIdx * 32 + 31]) shl 24);
                FatTime := Word(SectorBuf[EntryIdx * 32 + 22]) or (Word(SectorBuf[EntryIdx * 32 + 23]) shl 8);
                FatDate := Word(SectorBuf[EntryIdx * 32 + 24]) or (Word(SectorBuf[EntryIdx * 32 + 25]) shl 8);

                if (Attr and $10) <> 0 then
                begin
                  if (CleanName <> '.') and (CleanName <> '..') and (QTail < 64) then
                  begin
                    Inc(QTail);
                    DirQueue[QTail].Clust := StartClust;
                    DirQueue[QTail].Path := CurPath + CleanName + '\';
                  end;
                end;

                if (CleanName <> '.') and (CleanName <> '..') and WildcardMatch(Pattern, CleanName) then
                begin
                  if MatchCount < MaxResults then
                  begin
                    Inc(MatchCount);
                    Results[MatchCount - 1].DirPath := CurPath;
                    Results[MatchCount - 1].Name := CleanName;
                    Results[MatchCount - 1].Size := FileSizeVal;
                    Results[MatchCount - 1].Attr := Attr;
                    Results[MatchCount - 1].StartCluster := StartClust;
                    Results[MatchCount - 1].ParentCluster := CurClust;
                    Results[MatchCount - 1].IsDir := (Attr and $10) <> 0;
                    Results[MatchCount - 1].Year := 1980 + (FatDate shr 9);
                    Results[MatchCount - 1].Month := (FatDate shr 5) and 15;
                    Results[MatchCount - 1].Day := FatDate and 31;
                    Results[MatchCount - 1].Hour := FatTime shr 11;
                    Results[MatchCount - 1].Min := (FatTime shr 5) and 63;
                  end;
                end;
              end;
            end;
          end;
          CurrentOff := CurrentOff + 512;
        end;
        CurClust := GetFat12Entry(PByteArray(FatBuf), CurClust);
      end;
    end;
  end;

  SearchDiskRecursive := MatchCount;
end;

function ExportCatalogFile(var ImgF: file; DataAreaStart: LongInt;
  BytesPerCluster: Word; RootDirStart: LongInt; RootDirSectors: Word;
  SectorsPerCluster: Byte; TotalClusters, FreeClusters: Word;
  Tracks, Sides, SectorsPerTrack: Word; TotalBytes, FreeBytes: LongInt;
  FatBuf: Pointer; const ImgPath, OutPath: string; AsCSV: Boolean): Boolean;
var
  OutF: Text;
  DirQueue: array[1..64] of record
    Clust: Word;
    Path: string[36];
  end;
  QHead, QTail: Integer;
  CurClust: Word;
  CurPath: string[36];
  SectorBuf: array[0..511] of Byte;
  SecIdx, EntryIdx: Integer;
  CurrentOff: LongInt;
  ActualRead: Word;
  Attr: Byte;
  StartClust: Word;
  FileSizeVal: LongInt;
  CleanName: string[12];
  FatDate, FatTime: Word;
  Y, M, D, H, Min: Word;
  TotFiles, TotDirs: Integer;
  TotBytes: LongInt;
  DateStr, TimeStr, SizeStr, LineStr: string[30];
  SNum: string[12];
begin
  ExportCatalogFile := False;
  Assign(OutF, OutPath);
  Rewrite(OutF);
  if IOResult <> 0 then Exit;

  TotFiles := 0;
  TotDirs := 0;
  TotBytes := 0;

  if AsCSV then
  begin
    WriteLn(OutF, 'Path,Filename,Size,Attr,Date,Time,Cluster');
  end
  else
  begin
    WriteLn(OutF, '========================================================================');
    WriteLn(OutF, ' STIMAGE for DOS - Atari ST Disk Catalog Report');
    WriteLn(OutF, '========================================================================');
    WriteLn(OutF, ' Image:        ', ImgPath);
    WriteLn(OutF, ' Geometry:     ', TotalBytes div 1024, ' KB (', Tracks, ' Tracks, ', Sides, ' Sides, ',
      SectorsPerTrack, ' SPT)');
    WriteLn(OutF, ' Free Space:   ', FreeBytes div 1024, ' KB (', FreeClusters, ' clust free / ',
      TotalClusters, ' total)');
    WriteLn(OutF, '========================================================================');
    WriteLn(OutF, ' Path \ Name                   Size   Attr    Date       Time   Cluster ');
    WriteLn(OutF, '------------------------------------------------------------------------');
  end;

  QHead := 1; QTail := 1;
  DirQueue[1].Clust := 0;
  DirQueue[1].Path := '\';

  while (QHead <= QTail) do
  begin
    CurClust := DirQueue[QHead].Clust;
    CurPath := DirQueue[QHead].Path;
    Inc(QHead);

    if CurClust = 0 then
    begin
      CurrentOff := RootDirStart;
      for SecIdx := 0 to RootDirSectors - 1 do
      begin
        Seek(ImgF, CurrentOff);
        if IOResult <> 0 then Break;
        BlockRead(ImgF, SectorBuf, 512, ActualRead);
        if ActualRead < 512 then Break;

        for EntryIdx := 0 to 15 do
        begin
          if SectorBuf[EntryIdx * 32] = $00 then Break;
          if SectorBuf[EntryIdx * 32] <> $E5 then
          begin
            Attr := SectorBuf[EntryIdx * 32 + 11];
            if (Attr and $08) = 0 then
            begin
              CleanName := ExtractDirEntryName(@SectorBuf[EntryIdx * 32]);
              StartClust := Word(SectorBuf[EntryIdx * 32 + 26]) or (Word(SectorBuf[EntryIdx * 32 + 27]) shl 8);
              FileSizeVal := LongInt(SectorBuf[EntryIdx * 32 + 28]) or
                             (LongInt(SectorBuf[EntryIdx * 32 + 29]) shl 8) or
                             (LongInt(SectorBuf[EntryIdx * 32 + 30]) shl 16) or
                             (LongInt(SectorBuf[EntryIdx * 32 + 31]) shl 24);
              FatTime := Word(SectorBuf[EntryIdx * 32 + 22]) or (Word(SectorBuf[EntryIdx * 32 + 23]) shl 8);
              FatDate := Word(SectorBuf[EntryIdx * 32 + 24]) or (Word(SectorBuf[EntryIdx * 32 + 25]) shl 8);

              Y := 1980 + (FatDate shr 9);
              M := (FatDate shr 5) and 15;
              D := FatDate and 31;
              H := FatTime shr 11;
              Min := (FatTime shr 5) and 63;

              Str(Y:4, DateStr);
              if M < 10 then DateStr := DateStr + '-0' else DateStr := DateStr + '-';
              Str(M, SNum); DateStr := DateStr + SNum;
              if D < 10 then DateStr := DateStr + '-0' else DateStr := DateStr + '-';
              Str(D, SNum); DateStr := DateStr + SNum;

              if H < 10 then TimeStr := '0' else TimeStr := '';
              Str(H, SNum); TimeStr := TimeStr + SNum + ':';
              if Min < 10 then TimeStr := TimeStr + '0';
              Str(Min, SNum); TimeStr := TimeStr + SNum;

              if (Attr and $10) <> 0 then
              begin
                Inc(TotDirs);
                if (CleanName <> '.') and (CleanName <> '..') and (QTail < 64) then
                begin
                  Inc(QTail);
                  DirQueue[QTail].Clust := StartClust;
                  DirQueue[QTail].Path := CurPath + CleanName + '\';
                end;
                SizeStr := '<DIR>';
              end
              else
              begin
                Inc(TotFiles);
                TotBytes := TotBytes + FileSizeVal;
                SizeStr := FormatFileSize(FileSizeVal);
              end;

              if AsCSV then
              begin
                WriteLn(OutF, '"', CurPath, '",', CleanName, ',', FileSizeVal, ',', FormatAttr(Attr), ',',
                  DateStr, ',', TimeStr, ',', StartClust);
              end
              else
              begin
                LineStr := CurPath + CleanName;
                while Length(LineStr) < 28 do LineStr := LineStr + ' ';
                while Length(SizeStr) < 10 do SizeStr := ' ' + SizeStr;
                WriteLn(OutF, LineStr, ' ', SizeStr, '  ', FormatAttr(Attr), '  ', DateStr, ' ', TimeStr,
                  '  ', StartClust:5);
              end;
            end;
          end;
        end;
        CurrentOff := CurrentOff + 512;
      end;
    end
    else
    begin
      while (CurClust >= 2) and (CurClust < FAT12_EOC_MIN) do
      begin
        CurrentOff := DataAreaStart + LongInt(CurClust - 2) * BytesPerCluster;
        for SecIdx := 0 to SectorsPerCluster - 1 do
        begin
          Seek(ImgF, CurrentOff);
          if IOResult <> 0 then Break;
          BlockRead(ImgF, SectorBuf, 512, ActualRead);
          if ActualRead < 512 then Break;

          for EntryIdx := 0 to 15 do
          begin
            if SectorBuf[EntryIdx * 32] = $00 then Break;
            if SectorBuf[EntryIdx * 32] <> $E5 then
            begin
              Attr := SectorBuf[EntryIdx * 32 + 11];
              if (Attr and $08) = 0 then
              begin
                CleanName := ExtractDirEntryName(@SectorBuf[EntryIdx * 32]);
                if (CleanName <> '.') and (CleanName <> '..') then
                begin
                  StartClust := Word(SectorBuf[EntryIdx * 32 + 26]) or (Word(SectorBuf[EntryIdx * 32 + 27]) shl 8);
                  FileSizeVal := LongInt(SectorBuf[EntryIdx * 32 + 28]) or
                                 (LongInt(SectorBuf[EntryIdx * 32 + 29]) shl 8) or
                                 (LongInt(SectorBuf[EntryIdx * 32 + 30]) shl 16) or
                                 (LongInt(SectorBuf[EntryIdx * 32 + 31]) shl 24);
                  FatTime := Word(SectorBuf[EntryIdx * 32 + 22]) or (Word(SectorBuf[EntryIdx * 32 + 23]) shl 8);
                  FatDate := Word(SectorBuf[EntryIdx * 32 + 24]) or (Word(SectorBuf[EntryIdx * 32 + 25]) shl 8);

                  Y := 1980 + (FatDate shr 9);
                  M := (FatDate shr 5) and 15;
                  D := FatDate and 31;
                  H := FatTime shr 11;
                  Min := (FatTime shr 5) and 63;

                  Str(Y:4, DateStr);
                  if M < 10 then DateStr := DateStr + '-0' else DateStr := DateStr + '-';
                  Str(M, SNum); DateStr := DateStr + SNum;
                  if D < 10 then DateStr := DateStr + '-0' else DateStr := DateStr + '-';
                  Str(D, SNum); DateStr := DateStr + SNum;

                  if H < 10 then TimeStr := '0' else TimeStr := '';
                  Str(H, SNum); TimeStr := TimeStr + SNum + ':';
                  if Min < 10 then TimeStr := TimeStr + '0';
                  Str(Min, SNum); TimeStr := TimeStr + SNum;

                  if (Attr and $10) <> 0 then
                  begin
                    Inc(TotDirs);
                    if QTail < 64 then
                    begin
                      Inc(QTail);
                      DirQueue[QTail].Clust := StartClust;
                      DirQueue[QTail].Path := CurPath + CleanName + '\';
                    end;
                    SizeStr := '<DIR>';
                  end
                  else
                  begin
                    Inc(TotFiles);
                    TotBytes := TotBytes + FileSizeVal;
                    SizeStr := FormatFileSize(FileSizeVal);
                  end;

                  if AsCSV then
                  begin
                    WriteLn(OutF, '"', CurPath, '",', CleanName, ',', FileSizeVal, ',', FormatAttr(Attr), ',',
                      DateStr, ',', TimeStr, ',', StartClust);
                  end
                  else
                  begin
                    LineStr := CurPath + CleanName;
                    while Length(LineStr) < 28 do LineStr := LineStr + ' ';
                    while Length(SizeStr) < 10 do SizeStr := ' ' + SizeStr;
                    WriteLn(OutF, LineStr, ' ', SizeStr, '  ', FormatAttr(Attr), '  ', DateStr, ' ', TimeStr,
                      '  ', StartClust:5);
                  end;
                end;
              end;
            end;
          end;
          CurrentOff := CurrentOff + 512;
        end;
        CurClust := GetFat12Entry(PByteArray(FatBuf), CurClust);
      end;
    end;
  end;

  if not AsCSV then
  begin
    WriteLn(OutF, '------------------------------------------------------------------------');
    WriteLn(OutF, ' Total Files: ', TotFiles, ' (', FormatFileSize(TotBytes), ' Bytes)  |  Directories: ', TotDirs);
    WriteLn(OutF, '========================================================================');
  end;

  Close(OutF);
  ExportCatalogFile := True;
end;

function ImportDosFile(var ImgF: file; DataAreaStart: LongInt;
  BytesPerCluster: Word; RootDirStart: LongInt; RootDirSectors: Word;
  SectorsPerCluster: Byte; TotalClusters: Word; FatBuf: Pointer;
  CurrentDirClust: Word; const DosFilePath, TargetName: string;
  var ErrMsg: string): Boolean;
var
  DosF: file;
  DosSize: LongInt;
  ClustersNeeded: Word;
  AllocClust: array[1..800] of Word;
  AllocCount: Word;
  C: Word;
  Name8, Ext3: string;
  SlotOffset: LongInt;
  FoundSlot: Boolean;
  SectorBuf: array[0..511] of Byte;
  SecIdx, EntryIdx: Integer;
  CurrentOff: LongInt;
  ActualRead, ActualWrite: Word;
  ChunkBuf: array[0..4095] of Byte;
  I: Integer;
  ClustByteOff: LongInt;
  StartClust: Word;
  DirEntry: array[0..31] of Byte;
  FTime, FDate: Word;
  ToRead: Word;
begin
  ImportDosFile := False;
  ErrMsg := '';

  Assign(DosF, DosFilePath);
  Reset(DosF, 1);
  if IOResult <> 0 then
  begin
    ErrMsg := 'Cannot open DOS source file!';
    Exit;
  end;

  DosSize := FileSize(DosF);
  if not SanitizeTo83(TargetName, Name8, Ext3) then
  begin
    Close(DosF);
    ErrMsg := 'Invalid 8.3 target filename!';
    Exit;
  end;

  if DosSize = 0 then
    ClustersNeeded := 0
  else
    ClustersNeeded := (DosSize + BytesPerCluster - 1) div BytesPerCluster;

  { Find free clusters }
  AllocCount := 0;
  if ClustersNeeded > 0 then
  begin
    for C := 2 to TotalClusters + 1 do
    begin
      if GetFat12Entry(PByteArray(FatBuf), C) = FAT12_FREE then
      begin
        Inc(AllocCount);
        AllocClust[AllocCount] := C;
        if AllocCount = ClustersNeeded then Break;
      end;
    end;

    if AllocCount < ClustersNeeded then
    begin
      Close(DosF);
      ErrMsg := 'Not enough free space on disk image!';
      Exit;
    end;
  end;

  { Find free 32-byte slot in current directory }
  FoundSlot := False;
  SlotOffset := 0;

  if CurrentDirClust = 0 then
  begin
    CurrentOff := RootDirStart;
    for SecIdx := 0 to RootDirSectors - 1 do
    begin
      Seek(ImgF, CurrentOff);
      if IOResult <> 0 then Break;
      BlockRead(ImgF, SectorBuf, 512, ActualRead);
      if ActualRead < 512 then Break;

      for EntryIdx := 0 to 15 do
      begin
        if (SectorBuf[EntryIdx * 32] = $00) or (SectorBuf[EntryIdx * 32] = $E5) then
        begin
          SlotOffset := CurrentOff + (EntryIdx * 32);
          FoundSlot := True;
          Break;
        end;
      end;
      if FoundSlot then Break;
      CurrentOff := CurrentOff + 512;
    end;
  end
  else
  begin
    C := CurrentDirClust;
    while (C >= 2) and (C < FAT12_EOC_MIN) and (not FoundSlot) do
    begin
      CurrentOff := DataAreaStart + LongInt(C - 2) * BytesPerCluster;
      for SecIdx := 0 to SectorsPerCluster - 1 do
      begin
        Seek(ImgF, CurrentOff);
        if IOResult <> 0 then Break;
        BlockRead(ImgF, SectorBuf, 512, ActualRead);
        if ActualRead < 512 then Break;

        for EntryIdx := 0 to 15 do
        begin
          if (SectorBuf[EntryIdx * 32] = $00) or (SectorBuf[EntryIdx * 32] = $E5) then
          begin
            SlotOffset := CurrentOff + (EntryIdx * 32);
            FoundSlot := True;
            Break;
          end;
        end;
        if FoundSlot then Break;
        CurrentOff := CurrentOff + 512;
      end;
      if not FoundSlot then C := GetFat12Entry(PByteArray(FatBuf), C);
    end;
  end;

  if not FoundSlot then
  begin
    Close(DosF);
    ErrMsg := 'Directory table is full (no free slots)!';
    Exit;
  end;

  { Link clusters in FAT and write file content }
  if ClustersNeeded > 0 then
  begin
    for I := 1 to ClustersNeeded - 1 do
      SetFat12Entry(PByteArray(FatBuf), AllocClust[I], AllocClust[I + 1]);
    SetFat12Entry(PByteArray(FatBuf), AllocClust[ClustersNeeded], FAT12_EOC);

    for I := 1 to ClustersNeeded do
    begin
      ToRead := BytesPerCluster;
      if ToRead > SizeOf(ChunkBuf) then ToRead := SizeOf(ChunkBuf);
      FillChar(ChunkBuf, SizeOf(ChunkBuf), 0);
      BlockRead(DosF, ChunkBuf, ToRead, ActualRead);

      ClustByteOff := DataAreaStart + LongInt(AllocClust[I] - 2) * BytesPerCluster;
      Seek(ImgF, ClustByteOff);
      BlockWrite(ImgF, ChunkBuf, BytesPerCluster, ActualWrite);
    end;
    StartClust := AllocClust[1];
  end
  else
    StartClust := 0;

  Close(DosF);

  { Build 32-byte directory entry }
  FillChar(DirEntry, SizeOf(DirEntry), 0);
  for I := 0 to 7 do DirEntry[I] := Byte(' ');
  for I := 8 to 10 do DirEntry[I] := Byte(' ');
  for I := 1 to Length(Name8) do DirEntry[I - 1] := Byte(Name8[I]);
  for I := 1 to Length(Ext3) do DirEntry[7 + I] := Byte(Ext3[I]);
  DirEntry[11] := $20; { Archive attribute }

  GetCurrentDosTimeDate(FTime, FDate);
  DirEntry[22] := Byte(FTime and $FF);
  DirEntry[23] := Byte((FTime shr 8) and $FF);
  DirEntry[24] := Byte(FDate and $FF);
  DirEntry[25] := Byte((FDate shr 8) and $FF);

  DirEntry[26] := Byte(StartClust and $FF);
  DirEntry[27] := Byte((StartClust shr 8) and $FF);

  DirEntry[28] := Byte(DosSize and $FF);
  DirEntry[29] := Byte((DosSize shr 8) and $FF);
  DirEntry[30] := Byte((DosSize shr 16) and $FF);
  DirEntry[31] := Byte((DosSize shr 24) and $FF);

  Seek(ImgF, SlotOffset);
  BlockWrite(ImgF, DirEntry, 32, ActualWrite);

  ImportDosFile := True;
end;

function CreateSubdirectory(var ImgF: file; DataAreaStart: LongInt;
  BytesPerCluster: Word; RootDirStart: LongInt; RootDirSectors: Word;
  SectorsPerCluster: Byte; TotalClusters: Word; FatBuf: Pointer;
  CurrentDirClust: Word; const SubdirName: string;
  var ErrMsg: string): Boolean;
var
  NewClust: Word;
  C: Word;
  Name8, Ext3: string;
  SlotOffset: LongInt;
  FoundSlot: Boolean;
  SectorBuf: array[0..511] of Byte;
  ClustBuf: array[0..4095] of Byte;
  SecIdx, EntryIdx: Integer;
  CurrentOff: LongInt;
  ActualRead, ActualWrite: Word;
  FTime, FDate: Word;
  DirEntry: array[0..31] of Byte;
  I: Integer;
begin
  CreateSubdirectory := False;
  ErrMsg := '';

  if not SanitizeTo83(SubdirName, Name8, Ext3) then
  begin
    ErrMsg := 'Invalid folder name!';
    Exit;
  end;

  { Find 1 free cluster for the new directory table }
  NewClust := 0;
  for C := 2 to TotalClusters + 1 do
  begin
    if GetFat12Entry(PByteArray(FatBuf), C) = FAT12_FREE then
    begin
      NewClust := C;
      Break;
    end;
  end;

  if NewClust = 0 then
  begin
    ErrMsg := 'Disk is full! No free clusters available.';
    Exit;
  end;

  { Find free slot in parent directory }
  FoundSlot := False;
  SlotOffset := 0;

  if CurrentDirClust = 0 then
  begin
    CurrentOff := RootDirStart;
    for SecIdx := 0 to RootDirSectors - 1 do
    begin
      Seek(ImgF, CurrentOff);
      if IOResult <> 0 then Break;
      BlockRead(ImgF, SectorBuf, 512, ActualRead);
      if ActualRead < 512 then Break;

      for EntryIdx := 0 to 15 do
      begin
        if (SectorBuf[EntryIdx * 32] = $00) or (SectorBuf[EntryIdx * 32] = $E5) then
        begin
          SlotOffset := CurrentOff + (EntryIdx * 32);
          FoundSlot := True;
          Break;
        end;
      end;
      if FoundSlot then Break;
      CurrentOff := CurrentOff + 512;
    end;
  end
  else
  begin
    C := CurrentDirClust;
    while (C >= 2) and (C < FAT12_EOC_MIN) and (not FoundSlot) do
    begin
      CurrentOff := DataAreaStart + LongInt(C - 2) * BytesPerCluster;
      for SecIdx := 0 to SectorsPerCluster - 1 do
      begin
        Seek(ImgF, CurrentOff);
        if IOResult <> 0 then Break;
        BlockRead(ImgF, SectorBuf, 512, ActualRead);
        if ActualRead < 512 then Break;

        for EntryIdx := 0 to 15 do
        begin
          if (SectorBuf[EntryIdx * 32] = $00) or (SectorBuf[EntryIdx * 32] = $E5) then
          begin
            SlotOffset := CurrentOff + (EntryIdx * 32);
            FoundSlot := True;
            Break;
          end;
        end;
        if FoundSlot then Break;
        CurrentOff := CurrentOff + 512;
      end;
      if not FoundSlot then C := GetFat12Entry(PByteArray(FatBuf), C);
    end;
  end;

  if not FoundSlot then
  begin
    ErrMsg := 'Parent directory table is full!';
    Exit;
  end;

  { Mark cluster as EOC in FAT }
  SetFat12Entry(PByteArray(FatBuf), NewClust, FAT12_EOC);

  { Initialize new directory cluster with . and .. }
  FillChar(ClustBuf, SizeOf(ClustBuf), 0);
  GetCurrentDosTimeDate(FTime, FDate);

  { Entry 0: . (points to NewClust) }
  for I := 0 to 10 do ClustBuf[I] := Byte(' ');
  ClustBuf[0] := Byte('.');
  ClustBuf[11] := $10; { Directory attribute }
  ClustBuf[22] := Byte(FTime and $FF);
  ClustBuf[23] := Byte((FTime shr 8) and $FF);
  ClustBuf[24] := Byte(FDate and $FF);
  ClustBuf[25] := Byte((FDate shr 8) and $FF);
  ClustBuf[26] := Byte(NewClust and $FF);
  ClustBuf[27] := Byte((NewClust shr 8) and $FF);

  { Entry 1: .. (points to CurrentDirClust) }
  for I := 32 to 42 do ClustBuf[I] := Byte(' ');
  ClustBuf[32] := Byte('.');
  ClustBuf[33] := Byte('.');
  ClustBuf[43] := $10;
  ClustBuf[54] := Byte(FTime and $FF);
  ClustBuf[55] := Byte((FTime shr 8) and $FF);
  ClustBuf[56] := Byte(FDate and $FF);
  ClustBuf[57] := Byte((FDate shr 8) and $FF);
  ClustBuf[58] := Byte(CurrentDirClust and $FF);
  ClustBuf[59] := Byte((CurrentDirClust shr 8) and $FF);

  Seek(ImgF, DataAreaStart + LongInt(NewClust - 2) * BytesPerCluster);
  BlockWrite(ImgF, ClustBuf, BytesPerCluster, ActualWrite);

  { Write directory entry in parent directory }
  FillChar(DirEntry, SizeOf(DirEntry), 0);
  for I := 0 to 7 do DirEntry[I] := Byte(' ');
  for I := 8 to 10 do DirEntry[I] := Byte(' ');
  for I := 1 to Length(Name8) do DirEntry[I - 1] := Byte(Name8[I]);
  DirEntry[11] := $10; { Directory attribute }
  DirEntry[22] := Byte(FTime and $FF);
  DirEntry[23] := Byte((FTime shr 8) and $FF);
  DirEntry[24] := Byte(FDate and $FF);
  DirEntry[25] := Byte((FDate shr 8) and $FF);
  DirEntry[26] := Byte(NewClust and $FF);
  DirEntry[27] := Byte((NewClust shr 8) and $FF);

  Seek(ImgF, SlotOffset);
  BlockWrite(ImgF, DirEntry, 32, ActualWrite);

  CreateSubdirectory := True;
end;

function RenameDirEntry(var ImgF: file; EntryOffset: LongInt;
  const NewName8, NewExt3: string): Boolean;
var
  Buf: array[0..31] of Byte;
  Actual: Word;
  I: Integer;
begin
  RenameDirEntry := False;
  Seek(ImgF, EntryOffset);
  if IOResult <> 0 then Exit;
  BlockRead(ImgF, Buf, 32, Actual);
  if Actual < 32 then Exit;

  { Pad with spaces }
  FillChar(Buf[0], 11, 32);
  for I := 1 to Length(NewName8) do
    if I <= 8 then Buf[I - 1] := Ord(UpCase(NewName8[I]));
  for I := 1 to Length(NewExt3) do
    if I <= 3 then Buf[7 + I] := Ord(UpCase(NewExt3[I]));

  Seek(ImgF, EntryOffset);
  if IOResult <> 0 then Exit;
  BlockWrite(ImgF, Buf, 32, Actual);
  RenameDirEntry := (Actual = 32);
end;

function UpdateDirEntryAttr(var ImgF: file; EntryOffset: LongInt;
  NewAttr: Byte): Boolean;
var
  Actual: Word;
begin
  UpdateDirEntryAttr := False;
  Seek(ImgF, EntryOffset + 11);
  if IOResult <> 0 then Exit;
  BlockWrite(ImgF, NewAttr, 1, Actual);
  UpdateDirEntryAttr := (Actual = 1);
end;


function ExtractClusterChainToFile(var ImgF: file; DataAreaStart: LongInt;
  BytesPerCluster: Word; FatBuf: Pointer; StartClust: Word;
  FileSizeVal: LongInt; const DestPath: string): Boolean;
var
  DosF: file;
  Clust: Word;
  ClustOff, BytesRemaining: LongInt;
  ClusterBuf: array[0..4095] of Byte;
  ToRead, ActualRead: Word;
  ClustBytesRead: Word;
begin
  ExtractClusterChainToFile := False;
  if IOResult <> 0 then ;
  Assign(DosF, DestPath);
  Erase(DosF);
  if IOResult <> 0 then ;
  Assign(DosF, DestPath);
  Rewrite(DosF, 1);
  if IOResult <> 0 then Exit;

  BytesRemaining := FileSizeVal;
  Clust := StartClust;
  while (BytesRemaining > 0) and (Clust >= 2) and (Clust < FAT12_EOC_MIN) do
  begin
    ClustOff := DataAreaStart + (LongInt(Clust - 2) * BytesPerCluster);
    Seek(ImgF, ClustOff);
    if IOResult <> 0 then Break;

    ClustBytesRead := 0;
    while (BytesRemaining > 0) and (ClustBytesRead < BytesPerCluster) do
    begin
      ToRead := BytesPerCluster - ClustBytesRead;
      if ToRead > SizeOf(ClusterBuf) then ToRead := SizeOf(ClusterBuf);
      if LongInt(ToRead) > BytesRemaining then ToRead := Word(BytesRemaining);

      BlockRead(ImgF, ClusterBuf, ToRead, ActualRead);
      if (IOResult <> 0) or (ActualRead = 0) then Break;
      BlockWrite(DosF, ClusterBuf, ActualRead);
      if IOResult <> 0 then Break;

      Inc(ClustBytesRead, ActualRead);
      BytesRemaining := BytesRemaining - ActualRead;
    end;

    Clust := GetFat12Entry(PByteArray(FatBuf), Clust);
  end;
  Close(DosF);
  if IOResult <> 0 then ;
  ExtractClusterChainToFile := (BytesRemaining = 0);
end;

function ReadClusterChainBytes(var ImgF: file; DataAreaStart: LongInt;
  BytesPerCluster: Word; FatBuf: Pointer; StartCluster: Word;
  FileSizeVal, FileOffset: LongInt; var DestBuf; MaxBytes: Word): Word;
var
  Clust: Word;
  ClustOff: LongInt;
  BytesLeftInFile: LongInt;
  SkipClusters, OffsetInClust: LongInt;
  I: Integer;
  TotalRead, ToRead, ActualRead: Word;
  DestPtr: PByteArray;
begin
  TotalRead := 0;
  ReadClusterChainBytes := 0;
  if (StartCluster < 2) or (FileOffset >= FileSizeVal) or (MaxBytes = 0) then Exit;

  DestPtr := @DestBuf;
  BytesLeftInFile := FileSizeVal - FileOffset;
  if LongInt(MaxBytes) > BytesLeftInFile then
    MaxBytes := Word(BytesLeftInFile);

  SkipClusters := FileOffset div BytesPerCluster;
  OffsetInClust := FileOffset mod BytesPerCluster;

  Clust := StartCluster;
  for I := 1 to SkipClusters do
  begin
    if (Clust < 2) or (Clust >= FAT12_EOC_MIN) then Exit;
    Clust := GetFat12Entry(PByteArray(FatBuf), Clust);
  end;

  while (TotalRead < MaxBytes) and (Clust >= 2) and (Clust < FAT12_EOC_MIN) do
  begin
    ClustOff := DataAreaStart + (LongInt(Clust - 2) * BytesPerCluster) + OffsetInClust;
    Seek(ImgF, ClustOff);
    if IOResult <> 0 then Break;

    ToRead := BytesPerCluster - OffsetInClust;
    if ToRead > (MaxBytes - TotalRead) then
      ToRead := MaxBytes - TotalRead;

    BlockRead(ImgF, DestPtr^[TotalRead], ToRead, ActualRead);
    if ActualRead = 0 then Break;

    TotalRead := TotalRead + ActualRead;
    OffsetInClust := 0;
    Clust := GetFat12Entry(PByteArray(FatBuf), Clust);
  end;

  ReadClusterChainBytes := TotalRead;
end;

function FormatBlankDisk(const OutPath: string;
  SidesCount, SecPerTrk, TotalSec: Word): Boolean;
var
  F: file;
  BootSec: array[0..511] of Byte;
  FatInit: array[0..511] of Byte;
  EmptySec: array[0..511] of Byte;
  I: Integer;
begin
  FormatBlankDisk := False;
  Assign(F, OutPath);
  Rewrite(F, 1);
  if IOResult <> 0 then Exit;

  FillChar(BootSec, 512, 0);
  BootSec[$00] := $EB;
  BootSec[$01] := $38;
  BootSec[$02] := $90;
  BootSec[$03] := Ord('T'); BootSec[$04] := Ord('O'); BootSec[$05] := Ord('S');
  BootSec[$06] := 32;       BootSec[$07] := 32;       BootSec[$08] := 32;
  BootSec[$08] := $12; BootSec[$09] := $34; BootSec[$0A] := $56;
  BootSec[$0B] := $00; BootSec[$0C] := $02;
  BootSec[$0D] := 2;
  BootSec[$0E] := 1; BootSec[$0F] := 0;
  BootSec[$10] := 2;
  BootSec[$11] := 112; BootSec[$12] := 0;
  BootSec[$13] := TotalSec and $FF;
  BootSec[$14] := (TotalSec shr 8) and $FF;
  if SidesCount = 1 then BootSec[$15] := $FD else BootSec[$15] := $F9;
  if TotalSec > 1440 then
  begin
    BootSec[$16] := 5; BootSec[$17] := 0;
  end
  else
  begin
    BootSec[$16] := 3; BootSec[$17] := 0;
  end;
  BootSec[$18] := SecPerTrk and $FF; BootSec[$19] := 0;
  BootSec[$1A] := SidesCount and $FF; BootSec[$1B] := 0;

  BlockWrite(F, BootSec, 512);

  FillChar(FatInit, 512, 0);
  FatInit[0] := BootSec[$15];
  FatInit[1] := $FF;
  FatInit[2] := $FF;

  BlockWrite(F, FatInit, 512);
  FillChar(EmptySec, 512, 0);
  for I := 2 to BootSec[$16] do BlockWrite(F, EmptySec, 512);

  BlockWrite(F, FatInit, 512);
  for I := 2 to BootSec[$16] do BlockWrite(F, EmptySec, 512);

  for I := 1 to 7 do BlockWrite(F, EmptySec, 512);

  FillChar(EmptySec, 512, $E5);
  for I := (1 + (BootSec[$16] * 2) + 7) to TotalSec do
    BlockWrite(F, EmptySec, 512);

  Close(F);
  FormatBlankDisk := (IOResult = 0);
end;

function ExtractStoredZipMember(const ZipPath: string; LocalOff: LongInt;
  UncompSize: LongInt; const OutPath: string): Boolean;
var
  ZipF, OutF: file;
  LFH: TZipLFH;
  ReadBytes, ToRead: Word;
  BytesLeft: LongInt;
  CopyBuf: array[0..2047] of Byte;
begin
  ExtractStoredZipMember := False;
  Assign(ZipF, ZipPath);
  Reset(ZipF, 1);
  if IOResult <> 0 then Exit;

  Seek(ZipF, LocalOff);
  BlockRead(ZipF, LFH, SizeOf(LFH), ReadBytes);
  Seek(ZipF, FilePos(ZipF) + LFH.NameLen + LFH.ExtraLen);

  Assign(OutF, OutPath);
  Rewrite(OutF, 1);
  BytesLeft := UncompSize;
  while BytesLeft > 0 do
  begin
    ToRead := SizeOf(CopyBuf);
    if LongInt(ToRead) > BytesLeft then ToRead := Word(BytesLeft);
    BlockRead(ZipF, CopyBuf, ToRead, ReadBytes);
    if ReadBytes > 0 then BlockWrite(OutF, CopyBuf, ReadBytes);
    BytesLeft := BytesLeft - ReadBytes;
    if ReadBytes = 0 then Break;
  end;
  Close(OutF);
  Close(ZipF);
  ExtractStoredZipMember := (BytesLeft = 0);
end;

function CanRepackDiskTo720K(var SrcImgF: file; SrcDataStart: LongInt;
  SrcBytesPerClust: Word; SrcRootDirStart: LongInt; SrcRootDirSecs: Word;
  SrcSecPerClust: Byte; SrcFatBuf: Pointer; var TotalClustersNeeded: Word;
  var RootEntriesCount: Word; var TotalFileBytes: LongInt): Boolean;
var
  QHead, QTail: Integer;
  CurrClust: Word;
  SecIdx, EntryIdx: Integer;
  ActualRead: Word;
  DirFinished: Boolean;
  Attr: Byte;
  FSize: LongInt;
  Clust720: Word;
  NameStr: string[12];
  CurrOff: LongInt;
  I: Integer;
begin
  CanRepackDiskTo720K := False;
  TotalClustersNeeded := 0;
  RootEntriesCount := 0;
  TotalFileBytes := 0;

  QHead := 1;
  QTail := 1;
  CanRepackQueue[1] := 0;

  while (QHead <= QTail) and (QTail < 64) do
  begin
    CurrClust := CanRepackQueue[QHead];
    Inc(QHead);
    DirFinished := False;

    if CurrClust = 0 then
    begin
      for SecIdx := 0 to SrcRootDirSecs - 1 do
      begin
        if DirFinished then Break;
        Seek(SrcImgF, SrcRootDirStart + (LongInt(SecIdx) * 512));
        if IOResult <> 0 then Break;
        BlockRead(SrcImgF, CanRepackSectorBuf, 512, ActualRead);
        if ActualRead < 512 then Break;

        for EntryIdx := 0 to 15 do
        begin
          if CanRepackSectorBuf[EntryIdx * 32] = 0 then
          begin
            DirFinished := True;
            Break;
          end;
          if CanRepackSectorBuf[EntryIdx * 32] <> $E5 then
          begin
            Attr := CanRepackSectorBuf[EntryIdx * 32 + 11];
            if (Attr and $08 = 0) then
            begin
              Inc(RootEntriesCount);
              NameStr := '';
              for I := 0 to 7 do
                if CanRepackSectorBuf[EntryIdx * 32 + I] > 32 then
                  NameStr := NameStr + Chr(CanRepackSectorBuf[EntryIdx * 32 + I]);

              if (Attr and $10 <> 0) then
              begin
                if (NameStr <> '.') and (NameStr <> '..') then
                begin
                  Inc(TotalClustersNeeded);
                  if QTail < 64 then
                  begin
                    Inc(QTail);
                    CanRepackQueue[QTail] := (Word(CanRepackSectorBuf[EntryIdx * 32 + 27]) shl 8) or
                                       CanRepackSectorBuf[EntryIdx * 32 + 26];
                  end;
                end;
              end
              else
              begin
                FSize := LongInt(CanRepackSectorBuf[EntryIdx * 32 + 28]) or
                         (LongInt(CanRepackSectorBuf[EntryIdx * 32 + 29]) shl 8) or
                         (LongInt(CanRepackSectorBuf[EntryIdx * 32 + 30]) shl 16) or
                         (LongInt(CanRepackSectorBuf[EntryIdx * 32 + 31]) shl 24);
                TotalFileBytes := TotalFileBytes + FSize;
                if FSize > 0 then
                  Clust720 := (FSize + 1023) div 1024
                else
                  Clust720 := 0;
                TotalClustersNeeded := TotalClustersNeeded + Clust720;
              end;
            end;
          end;
        end;
      end;
    end
    else
    begin
      while (CurrClust >= 2) and (CurrClust < FAT12_EOC_MIN) and (not DirFinished) do
      begin
        CurrOff := SrcDataStart + (LongInt(CurrClust - 2) * SrcBytesPerClust);
        for SecIdx := 0 to SrcSecPerClust - 1 do
        begin
          if DirFinished then Break;
          Seek(SrcImgF, CurrOff + (LongInt(SecIdx) * 512));
          if IOResult <> 0 then Break;
          BlockRead(SrcImgF, CanRepackSectorBuf, 512, ActualRead);
          if ActualRead < 512 then Break;

          for EntryIdx := 0 to 15 do
          begin
            if CanRepackSectorBuf[EntryIdx * 32] = 0 then
            begin
              DirFinished := True;
              Break;
            end;
            if CanRepackSectorBuf[EntryIdx * 32] <> $E5 then
            begin
              Attr := CanRepackSectorBuf[EntryIdx * 32 + 11];
              if (Attr and $08 = 0) then
              begin
                NameStr := '';
                for I := 0 to 7 do
                  if CanRepackSectorBuf[EntryIdx * 32 + I] > 32 then
                    NameStr := NameStr + Chr(CanRepackSectorBuf[EntryIdx * 32 + I]);

                if (Attr and $10 <> 0) then
                begin
                  if (NameStr <> '.') and (NameStr <> '..') then
                  begin
                    Inc(TotalClustersNeeded);
                    if QTail < 64 then
                    begin
                      Inc(QTail);
                      CanRepackQueue[QTail] := (Word(CanRepackSectorBuf[EntryIdx * 32 + 27]) shl 8) or
                                         CanRepackSectorBuf[EntryIdx * 32 + 26];
                    end;
                  end;
                end
                else
                begin
                  FSize := LongInt(CanRepackSectorBuf[EntryIdx * 32 + 28]) or
                           (LongInt(CanRepackSectorBuf[EntryIdx * 32 + 29]) shl 8) or
                           (LongInt(CanRepackSectorBuf[EntryIdx * 32 + 30]) shl 16) or
                           (LongInt(CanRepackSectorBuf[EntryIdx * 32 + 31]) shl 24);
                  TotalFileBytes := TotalFileBytes + FSize;
                  if FSize > 0 then
                    Clust720 := (FSize + 1023) div 1024
                  else
                    Clust720 := 0;
                  TotalClustersNeeded := TotalClustersNeeded + Clust720;
                end;
              end;
            end;
          end;
        end;
        CurrClust := GetFat12Entry(PByteArray(SrcFatBuf), CurrClust);
      end;
    end;
  end;

  CanRepackDiskTo720K := (TotalClustersNeeded <= 713) and (RootEntriesCount <= 112);
end;

function RepackDiskTo720K(var SrcImgF: file; SrcDataStart: LongInt;
  SrcBytesPerClust: Word; SrcRootDirStart: LongInt; SrcRootDirSecs: Word;
  SrcSecPerClust: Byte; SrcFatBuf: Pointer; var SrcBootSector: array of Byte;
  const DestPath: string; var ErrMsg: string): Boolean;
var
  TotalClustersNeeded, RootEntriesCount: Word;
  TotalFileBytes: LongInt;
  DstF: file;
  QHead, QTail: Integer;
  NextFreeClust: Word;
  CurrSrcClust, CurrDstClust: Word;
  DstDirFileOff: LongInt;
  DstEntryIdx: Integer;
  SecIdx, EntryIdx: Integer;
  ActualRead: Word;
  DirFinished: Boolean;
  Attr: Byte;
  NameStr: string[12];
  NewSubDirClust, NextSubDirClust: Word;
  FSize: LongInt;
  SrcStartClust, NewFileClust: Word;
  ClustersNeeded, K: Word;
  BytesCopied: LongInt;
  ChunkFilled, ToTake, AvailInSrc: Word;
  SrcClustCurr, SrcClustByteOff: Word;
  DstClustOff: LongInt;
  I: Integer;
  CurSum, FixVal: Word;
begin
  RepackDiskTo720K := False;
  ErrMsg := '';

  if not CanRepackDiskTo720K(SrcImgF, SrcDataStart, SrcBytesPerClust,
                             SrcRootDirStart, SrcRootDirSecs, SrcSecPerClust,
                             SrcFatBuf, TotalClustersNeeded, RootEntriesCount,
                             TotalFileBytes) then
  begin
    if RootEntriesCount > 112 then
      ErrMsg := 'Root directory has > 112 entries!'
    else
      ErrMsg := 'Content (' + FormatNum((TotalFileBytes + 1023) div 1024) +
                ' KB) exceeds 720 KB!';
    Exit;
  end;

  if IOResult <> 0 then ;
  Assign(DstF, DestPath);
  Erase(DstF);
  if IOResult <> 0 then ;
  Rewrite(DstF, 1);
  if IOResult <> 0 then
  begin
    ErrMsg := 'Cannot create temporary 720KB image file!';
    Exit;
  end;

  if AtariBootChecksum(@SrcBootSector) = $1234 then
  begin
    Move(SrcBootSector, RepackDstBootSec, 512);
    RepackDstBootSec[$0B] := $00; RepackDstBootSec[$0C] := $02;
    RepackDstBootSec[$0D] := 2;
    RepackDstBootSec[$0E] := 1;   RepackDstBootSec[$0F] := 0;
    RepackDstBootSec[$10] := 2;
    RepackDstBootSec[$11] := 112; RepackDstBootSec[$12] := 0;
    RepackDstBootSec[$13] := 1440 and $FF;
    RepackDstBootSec[$14] := (1440 shr 8) and $FF;
    RepackDstBootSec[$15] := $F9;
    RepackDstBootSec[$16] := 3;   RepackDstBootSec[$17] := 0;
    RepackDstBootSec[$18] := 9;   RepackDstBootSec[$19] := 0;
    RepackDstBootSec[$1A] := 2;   RepackDstBootSec[$1B] := 0;
    RepackDstBootSec[$1C] := 0;   RepackDstBootSec[$1D] := 0;

    RepackDstBootSec[510] := 0; RepackDstBootSec[511] := 0;
    CurSum := AtariBootChecksum(@RepackDstBootSec);
    FixVal := ($1234 - CurSum) and $FFFF;
    RepackDstBootSec[510] := Byte(FixVal shr 8);
    RepackDstBootSec[511] := Byte(FixVal and $FF);
  end
  else
  begin
    FillChar(RepackDstBootSec, 512, 0);
    RepackDstBootSec[0] := $EB; RepackDstBootSec[1] := $38; RepackDstBootSec[2] := $90;
    RepackDstBootSec[3] := Ord('T'); RepackDstBootSec[4] := Ord('O'); RepackDstBootSec[5] := Ord('S');
    RepackDstBootSec[6] := 32;       RepackDstBootSec[7] := 32;       RepackDstBootSec[8] := 32;
    RepackDstBootSec[8] := $12;      RepackDstBootSec[9] := $34;      RepackDstBootSec[10] := $56;
    RepackDstBootSec[$0B] := $00; RepackDstBootSec[$0C] := $02;
    RepackDstBootSec[$0D] := 2;
    RepackDstBootSec[$0E] := 1; RepackDstBootSec[$0F] := 0;
    RepackDstBootSec[$10] := 2;
    RepackDstBootSec[$11] := 112; RepackDstBootSec[$12] := 0;
    RepackDstBootSec[$13] := 1440 and $FF;
    RepackDstBootSec[$14] := (1440 shr 8) and $FF;
    RepackDstBootSec[$15] := $F9;
    RepackDstBootSec[$16] := 3; RepackDstBootSec[$17] := 0;
    RepackDstBootSec[$18] := 9; RepackDstBootSec[$19] := 0;
    RepackDstBootSec[$1A] := 2; RepackDstBootSec[$1B] := 0;
    RepackDstBootSec[$1C] := 0; RepackDstBootSec[$1D] := 0;
    RepackDstBootSec[510] := $55;
    RepackDstBootSec[511] := $AA;
  end;
  BlockWrite(DstF, RepackDstBootSec, 512);

  FillChar(RepackZeroBuf, SizeOf(RepackZeroBuf), 0);
  for I := 1 to 359 do
    BlockWrite(DstF, RepackZeroBuf, 2048);
  BlockWrite(DstF, RepackZeroBuf, 1536);

  FillChar(RepackFatBuf720, 1536, 0);
  RepackFatBuf720[0] := $F9;
  RepackFatBuf720[1] := $FF;
  RepackFatBuf720[2] := $FF;

  NextFreeClust := 2;
  QHead := 1;
  QTail := 1;
  RepackQueue[1].SrcClust := 0;
  RepackQueue[1].DstClust := 0;

  while (QHead <= QTail) and (QTail < 64) do
  begin
    CurrSrcClust := RepackQueue[QHead].SrcClust;
    CurrDstClust := RepackQueue[QHead].DstClust;
    Inc(QHead);

    if CurrDstClust = 0 then
    begin
      DstDirFileOff := 3584;
      DstEntryIdx := 0;
    end
    else
    begin
      DstDirFileOff := 7168 + (LongInt(CurrDstClust - 2) * 1024);
      DstEntryIdx := 2;
    end;

    DirFinished := False;
    if CurrSrcClust = 0 then
    begin
      for SecIdx := 0 to SrcRootDirSecs - 1 do
      begin
        if DirFinished then Break;
        Seek(SrcImgF, SrcRootDirStart + (LongInt(SecIdx) * 512));
        if IOResult <> 0 then Break;
        BlockRead(SrcImgF, RepackSectorBuf, 512, ActualRead);
        if ActualRead < 512 then Break;

        for EntryIdx := 0 to 15 do
        begin
          if RepackSectorBuf[EntryIdx * 32] = 0 then
          begin
            DirFinished := True;
            Break;
          end;
          if RepackSectorBuf[EntryIdx * 32] <> $E5 then
          begin
            Move(RepackSectorBuf[EntryIdx * 32], RepackDirEntry, 32);
            Attr := RepackDirEntry[11];

            if (Attr and $08 <> 0) then
            begin
              if (CurrDstClust = 0) and (DstEntryIdx < 112) then
              begin
                Seek(DstF, DstDirFileOff + (LongInt(DstEntryIdx) * 32));
                BlockWrite(DstF, RepackDirEntry, 32);
                Inc(DstEntryIdx);
              end;
            end
            else
            begin
              NameStr := '';
              for I := 0 to 7 do
                if RepackDirEntry[I] > 32 then
                  NameStr := NameStr + Chr(RepackDirEntry[I]);

              if (Attr and $10 <> 0) then
              begin
                if (NameStr <> '.') and (NameStr <> '..') then
                begin
                  SrcStartClust := (Word(RepackDirEntry[27]) shl 8) or RepackDirEntry[26];
                  NewSubDirClust := NextFreeClust;
                  Inc(NextFreeClust);
                  SetFat12Entry(@RepackFatBuf720, NewSubDirClust, FAT12_EOC);

                  FillChar(RepackSubDirBuf, SizeOf(RepackSubDirBuf), 0);
                  Move(RepackDirEntry, RepackSubDirBuf[0], 32);
                  for I := 0 to 10 do RepackSubDirBuf[I] := 32;
                  RepackSubDirBuf[0] := Ord('.');
                  RepackSubDirBuf[11] := $10;
                  RepackSubDirBuf[26] := Byte(NewSubDirClust and $FF);
                  RepackSubDirBuf[27] := Byte((NewSubDirClust shr 8) and $FF);
                  RepackSubDirBuf[28] := 0; RepackSubDirBuf[29] := 0;
                  RepackSubDirBuf[30] := 0; RepackSubDirBuf[31] := 0;

                  Move(RepackDirEntry, RepackSubDirBuf[32], 32);
                  for I := 0 to 10 do RepackSubDirBuf[32 + I] := 32;
                  RepackSubDirBuf[32] := Ord('.');
                  RepackSubDirBuf[33] := Ord('.');
                  RepackSubDirBuf[32 + 11] := $10;
                  RepackSubDirBuf[32 + 26] := Byte(CurrDstClust and $FF);
                  RepackSubDirBuf[32 + 27] := Byte((CurrDstClust shr 8) and $FF);
                  RepackSubDirBuf[32 + 28] := 0; RepackSubDirBuf[32 + 29] := 0;
                  RepackSubDirBuf[32 + 30] := 0; RepackSubDirBuf[32 + 31] := 0;

                  Seek(DstF, 7168 + (LongInt(NewSubDirClust - 2) * 1024));
                  BlockWrite(DstF, RepackSubDirBuf, 64);

                  RepackDirEntry[26] := Byte(NewSubDirClust and $FF);
                  RepackDirEntry[27] := Byte((NewSubDirClust shr 8) and $FF);
                  RepackDirEntry[28] := 0; RepackDirEntry[29] := 0;
                  RepackDirEntry[30] := 0; RepackDirEntry[31] := 0;

                  Seek(DstF, DstDirFileOff + (LongInt(DstEntryIdx) * 32));
                  BlockWrite(DstF, RepackDirEntry, 32);
                  Inc(DstEntryIdx);

                  if QTail < 64 then
                  begin
                    Inc(QTail);
                    RepackQueue[QTail].SrcClust := SrcStartClust;
                    RepackQueue[QTail].DstClust := NewSubDirClust;
                  end;
                end;
              end
              else
              begin
                FSize := LongInt(RepackDirEntry[28]) or
                         (LongInt(RepackDirEntry[29]) shl 8) or
                         (LongInt(RepackDirEntry[30]) shl 16) or
                         (LongInt(RepackDirEntry[31]) shl 24);
                SrcStartClust := (Word(RepackDirEntry[27]) shl 8) or RepackDirEntry[26];

                if (FSize = 0) or (SrcStartClust < 2) then
                  NewFileClust := 0
                else
                begin
                  ClustersNeeded := (FSize + 1023) div 1024;
                  NewFileClust := NextFreeClust;
                  if LongInt(NewFileClust) + ClustersNeeded - 1 > 714 then
                  begin
                    ErrMsg := 'Destination disk full!';
                    Close(DstF);
                    Exit;
                  end;

                  if ClustersNeeded > 1 then
                    for K := 0 to ClustersNeeded - 2 do
                      SetFat12Entry(@RepackFatBuf720, NewFileClust + K, NewFileClust + K + 1);
                  SetFat12Entry(@RepackFatBuf720, NewFileClust + ClustersNeeded - 1, FAT12_EOC);

                  BytesCopied := 0;
                  SrcClustCurr := SrcStartClust;
                  SrcClustByteOff := 0;

                  for K := 0 to ClustersNeeded - 1 do
                  begin
                    FillChar(RepackChunkBuf, 1024, 0);
                    ChunkFilled := 0;

                    while (ChunkFilled < 1024) and (BytesCopied < FSize) and
                          (SrcClustCurr >= 2) and (SrcClustCurr < FAT12_EOC_MIN) do
                    begin
                      AvailInSrc := SrcBytesPerClust - SrcClustByteOff;
                      ToTake := 1024 - ChunkFilled;
                      if ToTake > AvailInSrc then ToTake := AvailInSrc;
                      if LongInt(ToTake) > (FSize - BytesCopied) then
                        ToTake := Word(FSize - BytesCopied);

                      Seek(SrcImgF, SrcDataStart + (LongInt(SrcClustCurr - 2) * SrcBytesPerClust) +
                           SrcClustByteOff);
                      BlockRead(SrcImgF, RepackChunkBuf[ChunkFilled], ToTake, ActualRead);
                      if ActualRead = 0 then Break;

                      Inc(ChunkFilled, ActualRead);
                      Inc(BytesCopied, ActualRead);
                      Inc(SrcClustByteOff, ActualRead);
                      if SrcClustByteOff >= SrcBytesPerClust then
                      begin
                        SrcClustCurr := GetFat12Entry(PByteArray(SrcFatBuf), SrcClustCurr);
                        SrcClustByteOff := 0;
                      end;
                    end;

                    DstClustOff := 7168 + (LongInt(NewFileClust + K - 2) * 1024);
                    Seek(DstF, DstClustOff);
                    BlockWrite(DstF, RepackChunkBuf, 1024);
                  end;

                  Inc(NextFreeClust, ClustersNeeded);
                end;

                RepackDirEntry[26] := Byte(NewFileClust and $FF);
                RepackDirEntry[27] := Byte((NewFileClust shr 8) and $FF);
                Seek(DstF, DstDirFileOff + (LongInt(DstEntryIdx) * 32));
                BlockWrite(DstF, RepackDirEntry, 32);
                Inc(DstEntryIdx);
              end;
            end;
          end;
        end;
      end;
    end
    else
    begin
      while (CurrSrcClust >= 2) and (CurrSrcClust < FAT12_EOC_MIN) and (not DirFinished) do
      begin
        for SecIdx := 0 to SrcSecPerClust - 1 do
        begin
          if DirFinished then Break;
          Seek(SrcImgF, SrcDataStart + (LongInt(CurrSrcClust - 2) * SrcBytesPerClust) +
               (LongInt(SecIdx) * 512));
          if IOResult <> 0 then Break;
          BlockRead(SrcImgF, RepackSectorBuf, 512, ActualRead);
          if ActualRead < 512 then Break;

          for EntryIdx := 0 to 15 do
          begin
            if RepackSectorBuf[EntryIdx * 32] = 0 then
            begin
              DirFinished := True;
              Break;
            end;
            if RepackSectorBuf[EntryIdx * 32] <> $E5 then
            begin
              Move(RepackSectorBuf[EntryIdx * 32], RepackDirEntry, 32);
              Attr := RepackDirEntry[11];
              if (Attr and $08 = 0) then
              begin
                NameStr := '';
                for I := 0 to 7 do
                  if RepackDirEntry[I] > 32 then
                    NameStr := NameStr + Chr(RepackDirEntry[I]);

                if (Attr and $10 <> 0) then
                begin
                  if (NameStr <> '.') and (NameStr <> '..') then
                  begin
                    SrcStartClust := (Word(RepackDirEntry[27]) shl 8) or RepackDirEntry[26];
                    NewSubDirClust := NextFreeClust;
                    Inc(NextFreeClust);
                    SetFat12Entry(@RepackFatBuf720, NewSubDirClust, FAT12_EOC);

                    FillChar(RepackSubDirBuf, SizeOf(RepackSubDirBuf), 0);
                    Move(RepackDirEntry, RepackSubDirBuf[0], 32);
                    for I := 0 to 10 do RepackSubDirBuf[I] := 32;
                    RepackSubDirBuf[0] := Ord('.');
                    RepackSubDirBuf[11] := $10;
                    RepackSubDirBuf[26] := Byte(NewSubDirClust and $FF);
                    RepackSubDirBuf[27] := Byte((NewSubDirClust shr 8) and $FF);
                    RepackSubDirBuf[28] := 0; RepackSubDirBuf[29] := 0;
                    RepackSubDirBuf[30] := 0; RepackSubDirBuf[31] := 0;

                    Move(RepackDirEntry, RepackSubDirBuf[32], 32);
                    for I := 0 to 10 do RepackSubDirBuf[32 + I] := 32;
                    RepackSubDirBuf[32] := Ord('.');
                    RepackSubDirBuf[33] := Ord('.');
                    RepackSubDirBuf[32 + 11] := $10;
                    RepackSubDirBuf[32 + 26] := Byte(CurrDstClust and $FF);
                    RepackSubDirBuf[32 + 27] := Byte((CurrDstClust shr 8) and $FF);
                    RepackSubDirBuf[32 + 28] := 0; RepackSubDirBuf[32 + 29] := 0;
                    RepackSubDirBuf[32 + 30] := 0; RepackSubDirBuf[32 + 31] := 0;

                    Seek(DstF, 7168 + (LongInt(NewSubDirClust - 2) * 1024));
                    BlockWrite(DstF, RepackSubDirBuf, 64);

                    RepackDirEntry[26] := Byte(NewSubDirClust and $FF);
                    RepackDirEntry[27] := Byte((NewSubDirClust shr 8) and $FF);
                    RepackDirEntry[28] := 0; RepackDirEntry[29] := 0;
                    RepackDirEntry[30] := 0; RepackDirEntry[31] := 0;

                    if DstEntryIdx >= 32 then
                    begin
                      NextSubDirClust := NextFreeClust;
                      Inc(NextFreeClust);
                      SetFat12Entry(@RepackFatBuf720, CurrDstClust, NextSubDirClust);
                      SetFat12Entry(@RepackFatBuf720, NextSubDirClust, FAT12_EOC);
                      CurrDstClust := NextSubDirClust;
                      DstDirFileOff := 7168 + (LongInt(CurrDstClust - 2) * 1024);
                      DstEntryIdx := 0;
                    end;

                    Seek(DstF, DstDirFileOff + (LongInt(DstEntryIdx) * 32));
                    BlockWrite(DstF, RepackDirEntry, 32);
                    Inc(DstEntryIdx);

                    if QTail < 64 then
                    begin
                      Inc(QTail);
                      RepackQueue[QTail].SrcClust := SrcStartClust;
                      RepackQueue[QTail].DstClust := NewSubDirClust;
                    end;
                  end;
                end
                else
                begin
                  FSize := LongInt(RepackDirEntry[28]) or
                           (LongInt(RepackDirEntry[29]) shl 8) or
                           (LongInt(RepackDirEntry[30]) shl 16) or
                           (LongInt(RepackDirEntry[31]) shl 24);
                  SrcStartClust := (Word(RepackDirEntry[27]) shl 8) or RepackDirEntry[26];

                  if (FSize = 0) or (SrcStartClust < 2) then
                    NewFileClust := 0
                  else
                  begin
                    ClustersNeeded := (FSize + 1023) div 1024;
                    NewFileClust := NextFreeClust;
                    if LongInt(NewFileClust) + ClustersNeeded - 1 > 714 then
                    begin
                      ErrMsg := 'Destination disk full!';
                      Close(DstF);
                      Exit;
                    end;

                    if ClustersNeeded > 1 then
                      for K := 0 to ClustersNeeded - 2 do
                        SetFat12Entry(@RepackFatBuf720, NewFileClust + K, NewFileClust + K + 1);
                    SetFat12Entry(@RepackFatBuf720, NewFileClust + ClustersNeeded - 1, FAT12_EOC);

                    BytesCopied := 0;
                    SrcClustCurr := SrcStartClust;
                    SrcClustByteOff := 0;

                    for K := 0 to ClustersNeeded - 1 do
                    begin
                      FillChar(RepackChunkBuf, 1024, 0);
                      ChunkFilled := 0;

                      while (ChunkFilled < 1024) and (BytesCopied < FSize) and
                            (SrcClustCurr >= 2) and (SrcClustCurr < FAT12_EOC_MIN) do
                      begin
                        AvailInSrc := SrcBytesPerClust - SrcClustByteOff;
                        ToTake := 1024 - ChunkFilled;
                        if ToTake > AvailInSrc then ToTake := AvailInSrc;
                        if LongInt(ToTake) > (FSize - BytesCopied) then
                          ToTake := Word(FSize - BytesCopied);

                        Seek(SrcImgF, SrcDataStart + (LongInt(SrcClustCurr - 2) * SrcBytesPerClust) +
                             SrcClustByteOff);
                        BlockRead(SrcImgF, RepackChunkBuf[ChunkFilled], ToTake, ActualRead);
                        if ActualRead = 0 then Break;

                        Inc(ChunkFilled, ActualRead);
                        Inc(BytesCopied, ActualRead);
                        Inc(SrcClustByteOff, ActualRead);
                        if SrcClustByteOff >= SrcBytesPerClust then
                        begin
                          SrcClustCurr := GetFat12Entry(PByteArray(SrcFatBuf), SrcClustCurr);
                          SrcClustByteOff := 0;
                        end;
                      end;

                      DstClustOff := 7168 + (LongInt(NewFileClust + K - 2) * 1024);
                      Seek(DstF, DstClustOff);
                      BlockWrite(DstF, RepackChunkBuf, 1024);
                    end;

                    Inc(NextFreeClust, ClustersNeeded);
                  end;

                  RepackDirEntry[26] := Byte(NewFileClust and $FF);
                  RepackDirEntry[27] := Byte((NewFileClust shr 8) and $FF);

                  if DstEntryIdx >= 32 then
                  begin
                    NextSubDirClust := NextFreeClust;
                    Inc(NextFreeClust);
                    SetFat12Entry(@RepackFatBuf720, CurrDstClust, NextSubDirClust);
                    SetFat12Entry(@RepackFatBuf720, NextSubDirClust, FAT12_EOC);
                    CurrDstClust := NextSubDirClust;
                    DstDirFileOff := 7168 + (LongInt(CurrDstClust - 2) * 1024);
                    DstEntryIdx := 0;
                  end;

                  Seek(DstF, DstDirFileOff + (LongInt(DstEntryIdx) * 32));
                  BlockWrite(DstF, RepackDirEntry, 32);
                  Inc(DstEntryIdx);
                end;
              end;
            end;
          end;
        end;
        CurrSrcClust := GetFat12Entry(PByteArray(SrcFatBuf), CurrSrcClust);
      end;
    end;
  end;

  Seek(DstF, 512);
  BlockWrite(DstF, RepackFatBuf720, 1536);
  Seek(DstF, 2048);
  BlockWrite(DstF, RepackFatBuf720, 1536);

  Close(DstF);
  RepackDiskTo720K := (IOResult = 0);
end;

function LoadDiskBootAndBPB(var ImgF: file; var BPB: TAtariBPB;
  var Layout: TDiskLayout; var RawBootSector: array of Byte;
  FatBuf: Pointer; MaxFatBuf: Word): Boolean;
var
  ActualRead: Word;
  I: Integer;
  RawTotalSec: Word;
  ImgBytes: LongInt;
begin
  LoadDiskBootAndBPB := False;
  FillChar(BPB, SizeOf(BPB), 0);
  FillChar(RawBootSector, 512, 0);

  Seek(ImgF, 0);
  if IOResult <> 0 then Exit;

  BlockRead(ImgF, RawBootSector, 512, ActualRead);
  if (IOResult <> 0) or (ActualRead < 512) then Exit;

  ImgBytes := FileSize(ImgF);

  { OEM Name (Offsets $02..$07) }
  BPB.OEMName := '';
  for I := $02 to $07 do
  begin
    if (RawBootSector[I] >= 32) and (RawBootSector[I] <= 126) then
      BPB.OEMName := BPB.OEMName + Chr(RawBootSector[I])
    else
      BPB.OEMName := BPB.OEMName + '.';
  end;

  { Atari 24-bit Serial Number (Offsets $08..$0A) }
  BPB.DiskSerial := (LongInt(RawBootSector[$08]) shl 16) or
                    (LongInt(RawBootSector[$09]) shl 8) or
                    LongInt(RawBootSector[$0A]);

  { BPB Standard Fields }
  BPB.BytesPerSector    := ReadLE16(@RawBootSector, $0B);
  BPB.SectorsPerCluster := RawBootSector[$0D];
  BPB.ReservedSectors   := ReadLE16(@RawBootSector, $0E);
  BPB.NumberOfFATs      := RawBootSector[$10];
  BPB.RootEntries       := ReadLE16(@RawBootSector, $11);
  RawTotalSec           := ReadLE16(@RawBootSector, $13);
  BPB.MediaDescriptor   := RawBootSector[$15];
  BPB.SectorsPerFAT     := ReadLE16(@RawBootSector, $16);
  BPB.SectorsPerTrack   := ReadLE16(@RawBootSector, $18);
  BPB.Sides             := ReadLE16(@RawBootSector, $1A);
  BPB.HiddenSectors     := ReadLE16(@RawBootSector, $1C);

  BPB.BootChecksum      := AtariBootChecksum(@RawBootSector);
  BPB.IsExecBoot        := (BPB.BootChecksum = ATARI_BOOT_EXEC_SUM);
  BPB.IsPlausible       := True;

  { Sanitize and apply fallbacks for non-standard Atari images }
  if BPB.BytesPerSector <> 512 then
  begin
    BPB.BytesPerSector := 512;
    BPB.IsPlausible := False;
  end;

  if not (BPB.SectorsPerCluster in [1, 2, 4]) then
  begin
    BPB.SectorsPerCluster := 2;
    BPB.IsPlausible := False;
  end;

  if (BPB.ReservedSectors < 1) or (BPB.ReservedSectors > 32) then
  begin
    BPB.ReservedSectors := 1;
    BPB.IsPlausible := False;
  end;

  if not (BPB.NumberOfFATs in [1, 2]) then
  begin
    BPB.NumberOfFATs := 2;
    BPB.IsPlausible := False;
  end;

  if (BPB.RootEntries < 16) or (BPB.RootEntries > 1024) then
  begin
    BPB.RootEntries := 112;
    BPB.IsPlausible := False;
  end;

  if RawTotalSec = 0 then
    BPB.TotalSectors := ImgBytes div 512
  else
    BPB.TotalSectors := RawTotalSec;

  if (BPB.SectorsPerFAT < 1) or (BPB.SectorsPerFAT > 16) then
  begin
    BPB.SectorsPerFAT := 3; { Default for 720K }
    BPB.IsPlausible := False;
  end;

  if (BPB.SectorsPerTrack < 8) or (BPB.SectorsPerTrack > 21) then
  begin
    BPB.SectorsPerTrack := 9;
    BPB.IsPlausible := False;
  end;

  if not (BPB.Sides in [1, 2]) then
  begin
    if ImgBytes <= 409600 then
      BPB.Sides := 1
    else
      BPB.Sides := 2;
  end;

  { Calculate Disk Layout }
  Layout.BytesPerCluster := Word(BPB.SectorsPerCluster) * BPB.BytesPerSector;
  Layout.SingleFATSize   := LongInt(BPB.SectorsPerFAT) * BPB.BytesPerSector;
  Layout.FatTableStart   := LongInt(BPB.ReservedSectors) * BPB.BytesPerSector;
  Layout.RootDirStart    := Layout.FatTableStart + (LongInt(BPB.NumberOfFATs) * Layout.SingleFATSize);
  Layout.RootDirSectors  := ((LongInt(BPB.RootEntries) * 32) + (BPB.BytesPerSector - 1)) div BPB.BytesPerSector;
  Layout.RootDirBytes    := LongInt(Layout.RootDirSectors) * BPB.BytesPerSector;
  Layout.DataAreaStart   := Layout.RootDirStart + Layout.RootDirBytes;

  Layout.TotalBytes      := LongInt(BPB.TotalSectors) * BPB.BytesPerSector;
  if Layout.TotalBytes > ImgBytes then
    Layout.TotalBytes := ImgBytes;

  Layout.Sides := BPB.Sides;
  if Layout.Sides = 0 then Layout.Sides := 2;
  Layout.SectorsPerTrack := BPB.SectorsPerTrack;
  if Layout.SectorsPerTrack = 0 then Layout.SectorsPerTrack := 9;
  Layout.TotalSectors := BPB.TotalSectors;
  if (Layout.Sides > 0) and (Layout.SectorsPerTrack > 0) then
    Layout.Tracks := Layout.TotalSectors div (Layout.Sides * Layout.SectorsPerTrack)
  else
    Layout.Tracks := 80;
  if Layout.Tracks = 0 then Layout.Tracks := 80;

  if Layout.BytesPerCluster > 0 then
    Layout.TotalClusters := (Layout.TotalBytes - Layout.DataAreaStart) div Layout.BytesPerCluster
  else
    Layout.TotalClusters := 0;

  { Read FAT table into memory buffer }
  if FatBuf <> nil then
  begin
    FillChar(FatBuf^, MaxFatBuf, 0);
    Seek(ImgF, Layout.FatTableStart);
    if IOResult = 0 then
    begin
      if Layout.SingleFATSize > MaxFatBuf then
        BlockRead(ImgF, FatBuf^, MaxFatBuf, ActualRead)
      else
        BlockRead(ImgF, FatBuf^, Layout.SingleFATSize, ActualRead);
    end;
  end;

  LoadDiskBootAndBPB := True;
end;

procedure CalcDiskFreeSpace(var Layout: TDiskLayout; FatBuf: Pointer);
var
  Clust: Word;
  FreeCount: Word;
begin
  FreeCount := 0;
  for Clust := 2 to Layout.TotalClusters + 1 do
  begin
    if GetFat12Entry(PByteArray(FatBuf), Clust) = 0 then
      Inc(FreeCount);
  end;
  Layout.FreeClusters := FreeCount;
  Layout.FreeBytes := LongInt(FreeCount) * Layout.BytesPerCluster;
end;

procedure FlushDiskFAT(var ImgF: file; const Layout: TDiskLayout;
  NumberOfFATs: Byte; FatBuf: Pointer; MaxFatBuf: Word);
var
  I: Integer;
  FatOffset: LongInt;
  BytesToWrite: Word;
begin
  BytesToWrite := Layout.SingleFATSize;
  if BytesToWrite > MaxFatBuf then BytesToWrite := MaxFatBuf;
  for I := 0 to NumberOfFATs - 1 do
  begin
    FatOffset := Layout.FatTableStart + (LongInt(I) * Layout.SingleFATSize);
    Seek(ImgF, FatOffset);
    if IOResult = 0 then
      BlockWrite(ImgF, FatBuf^, BytesToWrite);
  end;
end;

procedure CopyDosFile(const SrcPath, DstPath: string);
var
  SF, DF: file;
  Buf: array[0..2047] of Byte;
  NumR, NumW: Word;
begin
  if IOResult <> 0 then ;
  Assign(SF, SrcPath);
  Reset(SF, 1);
  if IOResult <> 0 then Exit;
  Assign(DF, DstPath);
  Erase(DF);
  if IOResult <> 0 then ;
  Rewrite(DF, 1);
  if IOResult <> 0 then begin Close(SF); Exit; end;
  repeat
    BlockRead(SF, Buf, SizeOf(Buf), NumR);
    if NumR > 0 then
      BlockWrite(DF, Buf, NumR, NumW);
  until (NumR = 0) or (IOResult <> 0);
  Close(SF);
  Close(DF);
  if IOResult <> 0 then ;
end;

function ParseDirEntry(P: Pointer; FileOffset: LongInt; var Item: TDiskItem): Boolean;
var
  B: PByteArray;
  I: Integer;
  FirstChar: Byte;
  NamePart, ExtPart: string[8];
  TimeW, DateW: Word;
begin
  ParseDirEntry := False;
  B := P;
  FirstChar := B^[0];

  { $00 indicates definitive end of directory entries }
  if FirstChar = $00 then Exit;

  Item.EntryOffset := FileOffset;
  Item.IsDeleted := (FirstChar = $E5);

  { Read & sanitize 8-char filename }
  NamePart := '';
  for I := 0 to 7 do
  begin
    if (I = 0) and Item.IsDeleted then
      NamePart := NamePart + '_'
    else if B^[I] <> 32 then
    begin
      { Reject entries with non-printable control characters }
      if (B^[I] < 32) or (B^[I] > 126) then Exit;
      NamePart := NamePart + Chr(B^[I]);
    end;
  end;

  { Read & sanitize 3-char extension }
  ExtPart := '';
  for I := 8 to 10 do
  begin
    if B^[I] <> 32 then
    begin
      if (B^[I] < 32) or (B^[I] > 126) then Exit;
      ExtPart := ExtPart + Chr(B^[I]);
    end;
  end;

  Item.Attr := B^[11];
  { Reject invalid attribute combinations }
  if Item.Attr > $3F then Exit;

  Item.IsDir := (Item.Attr and $10) <> 0;
  Item.IsHidden := (Item.Attr and $02) <> 0;

  { Ignore Volume Labels in normal file listing }
  if (Item.Attr and $08) <> 0 then Exit;

  { Ignore '.' directory }
  if NamePart = '.' then Exit;

  TimeW := ReadLE16(P, 22);
  DateW := ReadLE16(P, 24);
  Item.StartCluster := ReadLE16(P, 26);
  Item.Size := ReadLE32(P, 28);

  Item.Hour := (TimeW shr 11) and 31;
  Item.Min  := (TimeW shr 5) and 63;
  Item.Sec  := (TimeW and 31) * 2;

  Item.Year := ((DateW shr 9) and 127) + 1980;
  Item.Month := (DateW shr 5) and 15;
  Item.Day  := DateW and 31;

  if ExtPart <> '' then
    Item.CleanName := NamePart + '.' + ExtPart
  else
    Item.CleanName := NamePart;

  Item.DisplayName := Item.CleanName;
  Item.PackerTag := '';
  ParseDirEntry := True;
end;
end.
