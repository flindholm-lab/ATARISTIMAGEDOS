# STIMAGE for MS-DOS (v2.1)

<img width="641" height="298" alt="image" src="https://github.com/user-attachments/assets/e702ce89-89a4-4739-842f-aa5efc9f26f7" />

A 16-bit real-mode MS-DOS port of the Atari ST Floppy Disk Image Manager, built with **Borland Turbo Pascal 7.0**.

Designed specifically for vintage PCs, DOSBox, and real-mode DOS environments without external dependencies.

---

## Key Highlights & Architecture

- **Zero CRT Dependency**: Does not use the Turbo Pascal `Crt` unit. Avoids the "Runtime Error 200: Division by Zero" on fast CPUs and DOSBox.
- **Top Pull-Down Menu Bar**: Clean Norton Commander / Turbo Vision style menu bar (`File`, `Image`, `View`, `Help`) with hotkeys (`Alt+F`, `Alt+I`, `Alt+V`, `Alt+H`, `F10`) and full submenu keyboard shortcuts.
- **Visual Host File Picker Dialog**: Automatically launches when no file is specified on startup or when choosing **Open Image** (`O`). Browse host DOS directories (`..` and subdirectories) and select `.ST`, `.MSA`, `.DIM`, or `.IMG` images.
- **Maximized Screen Real Estate**: All actions reside in the top drop-down menus and function bar, dedicating Rows 2..23 (20 visible lines) to the main Atari ST file listing and inspector panels.
- **16-Color CGA/EGA/VGA Text Mode**: Direct video memory access at `$B800:0000` (`Mode 03h`, 80x25).
- **Random Access Sector Streaming**: Does not load disk images into conventional RAM. Streams 512-byte sectors and cluster buffers on-demand. Total RAM usage is **under 32 KB**!
- **Pure FAT12 Engine with Strict Termination**:
  - Full BPB (BIOS Parameter Block) validation and geometry detection.
  - Strict `$00` directory termination preventing unformatted slack or garbage entries from appearing (e.g. `DUCKTALE.st` cleanly lists all 96 files and the `AUTO` directory).
  - 12-bit packed FAT entry decoding/encoding.
  - Subdirectory traversal and navigation.
  - Atari ST Boot Sector Checksum calculation (`$1234` executable boot sector indicator).
- **Atari ST Packer Signature Detection & Integrated Decompression Engine**:
  - Automatically identifies and transparently depacks **15 distinct Atari ST packer formats**:
    1. **Pack-Ice** (v2.4, v2.3, v2.2, v1.2, raw payloads and executable PRG stubs)
    2. **Rob Northen Compression (RNC)** (Method 1 and Method 2 raw streams and stubs)
    3. **Atomik Cruncher** (v3.5, v3.1, ATM5, ATM3, raw streams and executable stubs)
    4. **Pompey Pirates** (POPI, PUFF, v1.5, v1.8, v2.0, v2.4, v3.0 executables & raw)
    5. **Automation Packer** (v2.x, v3.x, v5.01, LSD!, LSD$, AUTM, LSDC, AU5!, AU5C)
    6. **JAM Packer** (LSD!, LZH!, LZW!, JAM executables)
    7. **FIRE Packer** (v1.0 and v2.0 raw streams and executables)
    8. **PowerPacker** (PP20 and PX20 raw streams and executables)
    9. **Thunder Packer** (ATOM v1.0 and v1.1)
    10. **STOS Squasher** (SQSH data and pictures)
    11. **Degas Elite .PC1** (RLE interleaved bitplanes -> 32,034 B uncompressed .PI1)
    12. **Titus .PC1** (DuckTales Method 2 LZW -> 32,034 B uncompressed .PI1)
    13. **4PAK Executable Packer** (Executable scanner, dictionary unpack, GEMDOS header regeneration)
    14. **Sentry Packer** (v2.05 and v2.11 raw streams and executable stubs)
    15. **STAD Monochrome Image Decompressor (.PAC)**
- **Full Microsoft Mouse Driver (Int 33h) Support**:
  - Full mouse control across all interfaces: click top menu bar items (`File`, `Image`, `View`, `Help`), hover and click dropdown items, switch menus on Row 0, click outside menus to dismiss.
  - File List navigation: single-click selects file, double-click opens viewer or executes directory traversal.
  - Interactive viewer: click Row 1 mode tabs to toggle Depacked vs. Raw view, click Row 24 action buttons, click top menu bar.
  - Modal dialogs: click buttons, drives, or clusters directly.
- **Visual Atari ST Cluster Allocation Map (`M` / `F6`)**:
  - Full 60 x 15 (900 clusters) 2D visual disk layout map.
  - Glyph and color-coded cluster states: `·` Free ($17), `■` Used ($1A), `*` Active Selected File ($4E), `E` End-Of-Chain ($1B), `B` Bad Sector ($74), with inverse cursor block ($70).
  - Physical CHS calculations: Cylinder, Head, Sector, byte offset, cluster status, next cluster pointer.
  - Intelligent directory owner scanning: identifies the exact owning file name and chain index (`Chain 1/78`).
  - Interactive navigation: cursor keys, mouse clicking, `Tab` to jump to next cluster in file chain, `Enter` / double-click to inspect cluster in Hex viewer.
- **Physical Floppy Disk Writer via BIOS / DOS Calls (`W`)**:
  - Direct low-level diskette imaging using BIOS `Int 13h` (AH=03h Write Sectors, AH=00h Reset Disk System).
  - Target drive selection: Drive `A:` or `B:` (3.5" 720KB/880KB/1.44MB diskettes).
  - Physical geometry verification: Cylinder, Head, and Sector calculation matched against Atari BPB layout.
  - Sector-by-sector and track-by-track streaming with write-protection detection, 3-stage reset/retry error recovery, and interactive progress bar.
- **Transparent & Unambiguous Viewing (Depacked vs. Raw Packed Stream)**:
  - **Dynamic View Menu Options**:
    - `[*] View DEPACKED Data    D`
    - `[ ] View RAW PACKED Stream D`
  - **Clickable Row 1 Header Banner**:
    - `[* DEPACKED: 178,813 B]  [  RAW: 78,638 B]  CARLODUK.PRG (-57%) | [D: Toggle]`
    - `[  DEPACKED: 178,813 B]  [* RAW: 78,638 B]  CARLODUK.PRG [RAW STREAM] | [D: Toggle]`
  - **Real-Time Toggle (`D` Key or Click)**: Instantly switch back and forth between decompressed data and raw packed stream.
  - **Direct Save (`[S]`)**: Export decompressed bytes directly to host DOS disk from within viewer.
  - **GEMDOS PRG Header Mode (`[T]` / `F3`)**: Inspect decompressed executable instructions or raw compressed startup stub.
- **Integrated File Viewers & External Graphic Viewer**:
  - `F3` / `Enter`: Text Viewer & GEMDOS `$601A` 68000 executable program header decoder (Text, Data, BSS, Symbol table sizes and initial disassembly).
  - `F4`: Full 16-byte Hex Dump viewer with ASCII column.
  - `Alt+V` / `Enter` (on pictures): High-resolution Graphics Viewer (`VIEW.EXE`).
    Supports:
    - **Atari ST Degas Elite `.PC1`** (RLE decompression, 320x200 16-color)
    - **Atari ST Degas `.PI1`** (Uncompressed 4-bitplane, 320x200 16-color)
    - **Atari ST NeoChrome `.NEO`** (Uncompressed 4-bitplane, 320x200 16-color)
    - **BMP, GIF, JPG** (VGA Mode 13h, EGA Mode 0Dh, CGA Mode 04h)

---


## Keyboard Controls & Shortcuts

| Shortcut | Menu / Action |
| :--- | :--- |
| **F10 / Alt+F** | Open **File** menu (Works in File List & View Mode) |
| **Alt+I** | Open **Image** menu |
| **Alt+V** | Open **View** menu / View with `VIEW.EXE` |
| **Alt+H** | Open **Help** menu |
| **O** | Open Image File Picker dialog |
| **Up / Down** | Move selection cursor up / down |
| **PgUp / PgDn** | Scroll one page (19 files) |
| **Home / End** | Jump to first / last file |
| **Tab** | In dialogs: toggle between **[ OK ]** and **[ Cancel ]** (or Action buttons) |
| **Enter** | Subdirectory: Enter (`..` goes up)<br>Graphic picture (`.PC1`, `.PI1`, `.NEO`, etc.): View with `VIEW.EXE`<br>File: Interactive File Viewer (Dual Hex & Text Columns) |
| **Backspace** | Go up to parent directory |
| **F1 / ?** | Quick Help Dialog |
| **F2 / B** | Detailed BPB / Disk Geometry & Boot Sector Inspector |
| **F3 / T** | View File (Text & GEMDOS `$601A` Executable Header Decoder) |
| **F4 / H** | Dual Hex & Text Columns Viewer (Offset, 16 hex bytes, ASCII) |
| **F5 / E** | Extract selected file to host DOS directory |
| **F6 / M** | **Visual Cluster Allocation Map** (2D 60x15 grid, CHS calculations, owner file chain jump) |
| **W** | **Write Image to Floppy Disk** (Direct BIOS / DOS Int 13h floppy writer) |
| **L** | **Create Image from Floppy Disk** (BIOS Int 13h reader, auto geometry, optional fit-in-720K repack) |
| **P** | **Depack & Extraction Manager** (Extract & depack any of the 15 supported formats to DOS) |
| **D (in Viewer)** | **Toggle View Mode**: Switch between **DEPACKED** and **RAW PACKED STREAM** |
| **S (in Viewer)** | **Save Depacked File**: Export decompressed bytes directly to host DOS disk |
| **F8 / Del** | Delete selected file (marks entry `$E5` and frees FAT clusters) |
| **U** | Undelete file marked with `*d*` |
| **F9** | Create New Blank Atari ST Disk Image (360K, 720K, 800K, 880K) |
| **Alt+X / Esc** | Exit cleanly to DOS prompt |

---

## Magic Shadow Archiver (.MSA) Support

STIMAGE for MS-DOS now natively supports **Magic Shadow Archiver (`.MSA`)** floppy disk images:
- **Header Decoding**: Detects `$0E0F` magic ID, sectors per track (9, 10, 11), single/double-sided format, and track ranges.
- **Track Decompression**: Automatically decompresses RLE-encoded and uncompressed tracks on the fly.
- **Full Manager Operations**: Browse directory contents, view files, view graphic pictures, inspect BPB and boot sector, and extract files directly from `.MSA` archives (`AWSM05.MSA`, `multi-depacker_1_0_[mug_uk].msa`, `Sewer Doc Disc #26.msa`, `TMB037.MSA`, `quantum_paintbox_eidersoft.MSA`).
- **Clean Lifecycle**: Automatically cleans up temporary staging files on image close or exit.

---
