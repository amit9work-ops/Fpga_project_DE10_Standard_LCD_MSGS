# DE10-Standard Full Run Guide (Step-by-Step)

This guide explains exactly how to run this project on a DE10-Standard board, including:

1. FPGA build and programming with Quartus.
2. Exact HPS files to place on the SD card.
3. Safe SD-card insertion/ejection procedures.
4. First successful run and validation checklist.

This guide assumes no prior Quartus experience.

---

## 1. What You Need

Hardware:

1. Terasic DE10-Standard board.
2. 12V power adapter for DE10-Standard.
3. MicroSD card with Linux image for DE10-Standard.
4. USB-Blaster cable (JTAG programming).
5. Ethernet cable (recommended for SSH/SCP file copy).

Software on Windows host:

1. Intel Quartus Prime Lite 21.1 (same version expected by project scripts).
2. PowerShell.
3. Optional but recommended: an SSH client (`ssh`, `scp`, or WinSCP).

Project location:

1. Project root folder:
   `Fpga_project_DE10_Standard_LCD_MSGS_-V2`

---

## 2. Safety Protocols (Read Before Doing Anything)

### 2.1 ESD and handling

1. Work on a non-conductive surface.
2. Touch a grounded metal object before touching the board.
3. Hold the board by the edges.

### 2.2 Safe SD-card insertion/removal protocol

Always follow this exact order:

1. Stop running app on board (`Ctrl+C` in terminal).
2. Run:
   ```bash
   sync
   sudo poweroff
   ```
3. Wait until board LEDs are off.
4. Disconnect board power.
5. Only now remove or insert the microSD card.

### 2.3 Safe SD-card ejection from PC

After copying files to the SD card on PC:

1. Close all open files/folders on that SD card.
2. Use OS eject/safely-remove:
   - Windows: `Safely Remove Hardware and Eject Media`
   - macOS: Finder `Eject`
   - Linux: `umount`
3. Wait for confirmation before physically removing the card.

### 2.4 Safe cable protocol

1. Connect/disconnect SD card only when DE10 power is OFF.
2. Connect USB-Blaster before powering board when possible.
3. Do not force connectors.

---

## 3. Quartus Build (Exactly What To Click)

This section assumes Quartus is already installed.

### 3.1 Fastest method (recommended): run provided script

1. Open PowerShell.
2. Go to the Quartus project folder:
   ```powershell
   cd .\Fpga_project_DE10_Standard_LCD_MSGS_-V2\hw\quartus
   ```
3. Run:
   ```powershell
   .\fix_then_build.ps1
   ```
4. Wait until you see success text:
   `Quartus Compilation Successful! Bitstream: DE10_Standard_GHRD.sof`

What this does automatically:

1. Qsys fix script.
2. Qsys generation.
3. Full Quartus compile.

### 3.2 Manual GUI method (if you want to do everything inside Quartus)

1. Open `Quartus Prime Lite 21.1`.
2. Click `File` -> `Open Project...`.
3. Browse to:
   `Fpga_project_DE10_Standard_LCD_MSGS_-V2\hw\quartus\DE10_Standard_GHRD.qpf`
4. Click `Open`.
5. In left panel `Tasks`, under `Compilation`, click `Start Compilation`.
6. Wait for compile to finish.
7. Confirm in messages/status that compilation is successful.
8. Confirm output file exists:
   `hw/quartus/output_files/DE10_Standard_GHRD.sof`

### 3.3 If compilation fails

1. Read the first red `Error` line in the `Messages` window.
2. If Qsys-related error appears, close Quartus and run:
   ```powershell
   cd .\Fpga_project_DE10_Standard_LCD_MSGS_-V2\hw\quartus
   .\fix_then_build.ps1
   ```
3. Re-open Quartus and compile again.
4. If script cannot find Quartus tools, verify expected install path:
   `C:\intelFPGA_lite\21.1\quartus`

---

## 4. Quartus Programmer (Exactly What To Click)

### 4.1 Cable and power order

1. Power OFF the DE10 board.
2. Connect USB-Blaster cable to PC and DE10 JTAG port.
3. Power ON the DE10 board.

### 4.2 Open programmer and select hardware

1. In Quartus, click `Tools` -> `Programmer`.
2. In Programmer window, click `Hardware Setup...`.
3. In `Currently selected hardware`, choose `USB-Blaster`.
4. Click `Close`.

If `USB-Blaster` is not listed:

1. Unplug/replug USB-Blaster.
2. Reopen `Hardware Setup...`.
3. Ensure board power is ON.

### 4.3 Load `.sof` and set options

1. Click `Add File...`.
2. Select:
   `Fpga_project_DE10_Standard_LCD_MSGS_-V2\hw\quartus\output_files\DE10_Standard_GHRD.sof`
3. Click `Open`.
4. In the file row, make sure `Program/Configure` is checked.
5. Leave mode as JTAG (default).

### 4.4 Program the FPGA

1. Click `Start`.
2. Watch progress bar.
3. Wait for status:
   `100% (Successful)`.

Only continue to HPS software steps after this success appears.

---

## 5. Exact Files Required on SD Card for HPS Build-On-Board

Create/copy these files into one folder on the board (recommended target: `/home/root/hps_app`).

Exact required files from `sw/hps_app/`:

1. `Makefile`
2. `main.c`
3. `LCD_Hw.c`
4. `LCD_Driver.c`
5. `LCD_Lib.c`
6. `lcd_graphic.c`
7. `font.c`
8. `terasic_lib.c`
9. `LCD_Hw.h`
10. `LCD_Driver.h`
11. `LCD_Lib.h`
12. `lcd_graphic.h`
13. `font.h`
14. `terasic_lib.h`
15. `terasic_os_includes.h`
16. `messages.h`

Notes:

1. `combined_test.c` is optional and not needed for `lcd_msg_app`.
2. Keep filenames and letter case exactly as-is.

---

## 6. Copy Files to the Board (Recommended Method: SSH/SCP)

This avoids repeatedly removing the SD card and reduces corruption risk.

### 6.1 Boot and network

1. Insert SD card while board power is OFF.
2. Connect Ethernet cable.
3. Power ON board and wait 1 to 2 minutes for Linux boot.

### 6.2 Find board IP

Use one of these:

1. Router DHCP client list (recommended).
2. If you have UART console access on the board, run:
   ```bash
   ip -4 addr show eth0
   ```
   Look for `inet A.B.C.D/...`.

### 6.3 First SSH login

From PC terminal:

```bash
ssh root@<BOARD_IP>
```

If asked to trust key, type `yes`.

If you get `REMOTE HOST IDENTIFICATION HAS CHANGED`:

```bash
ssh-keygen -R <BOARD_IP>
ssh root@<BOARD_IP>
```

### 6.4 Prepare destination folder on board

After SSH login:

```bash
mkdir -p /home/root/hps_app
df -h
exit
```

`df -h` verifies you have free disk space.

### 6.5 Copy exact files from PC

From your project root on PC:

```bash
scp sw/hps_app/Makefile \
    sw/hps_app/main.c \
    sw/hps_app/LCD_Hw.c \
    sw/hps_app/LCD_Driver.c \
    sw/hps_app/LCD_Lib.c \
    sw/hps_app/lcd_graphic.c \
    sw/hps_app/font.c \
    sw/hps_app/terasic_lib.c \
    sw/hps_app/LCD_Hw.h \
    sw/hps_app/LCD_Driver.h \
    sw/hps_app/LCD_Lib.h \
    sw/hps_app/lcd_graphic.h \
    sw/hps_app/font.h \
    sw/hps_app/terasic_lib.h \
    sw/hps_app/terasic_os_includes.h \
    sw/hps_app/messages.h \
    root@<BOARD_IP>:/home/root/hps_app/
```

### 6.6 Verify files really arrived

SSH again:

```bash
ssh root@<BOARD_IP>
cd /home/root/hps_app
ls -1
```

You should see all 16 required files.

---

## 7. Alternative: Copy via SD Card on PC (Offline Method)

Use this only if network copy is unavailable.

1. Follow Section 2.2 to power down and remove SD safely.
2. Insert SD card to PC.
3. Mount writable Linux partition.
4. Copy the 16 exact files listed in Section 5 into `/home/root/hps_app/`.
5. Follow Section 2.3 to eject SD safely from PC.
6. Insert SD back into DE10 only while power is OFF.
7. Power ON board.

---

## 8. Build and Run on the DE10 Board (Detailed Linux Terminal Flow)

Use this exact sequence on the board terminal (SSH or UART).

### 8.1 Login and enter project folder

```bash
ssh root@<BOARD_IP>
cd /home/root/hps_app
pwd
ls -la
```

`pwd` must print `/home/root/hps_app`.

Critical note (prevents the most common “LCD stuck” issue):

1. Always `cd` into the folder that contains the exact `main.c` you intend to build.
2. Always run `./lcd_msg_app` from that same folder.
   (If you have multiple copies like `/home/root/hps_app` and `~/hps_lcd`, it’s easy to edit one but build/run the other.)

### 8.2 Fix Windows line-ending issues (prevents common `make` failures)

Run this once after copying files from Windows:

```bash
sed -i 's/\r$//' Makefile *.c *.h
```

### 8.3 Confirm build tools exist

```bash
which make
which gcc
gcc --version
```

If `which gcc` is empty, install toolchain using your board distro package manager before continuing.

### 8.4 Build cleanly

```bash
make clean
make
```

Expected result:

1. Compilation commands for each `.c`.
2. Final linked binary named `lcd_msg_app`.

Verify binary exists:

```bash
ls -l lcd_msg_app
```

### 8.5 Run the application

```bash
./lcd_msg_app
```

Expected startup log lines include:

1. `Opening /dev/mem...`
2. `Memory mapping (HPS regs ...)`
3. `Memory mapping (LW bridge ...)`
4. `Initializing LCD...`
5. `LCD Ready.`
6. `=== LCD MESSAGE SYSTEM STARTED ===`

If these appear, Linux-side startup is correct.

Sanity check (must match): on startup, the app prints the LW offsets it uses, e.g.:

- `button_addr ... (LW + 0x0140)`
- `fsm_status_addr ... (LW + 0x0110)`
- `timer_status_addr ... (LW + 0x0100)`

If it prints `0x5000/0x6000/0x7000`, your HPS app is built with the wrong offsets and the LCD will not follow the FPGA FSM.

### 8.6 Stop app safely

1. Press `Ctrl+C`.
2. Confirm it prints clean shutdown message.

---

## 9. First-Pass Functional Check (Must Pass)

After app starts:

1. LCD should show idle/intro screen.
2. Press any key: IDLE to HOME transition.
3. Press `KEY1` or `KEY2` in HOME: enter MSG mode.
4. In MSG:
   - `KEY1`: next message
   - `KEY2`: previous message
   - `KEY0`: back to HOME
   - HEX0/HEX1 on the board should show the current message number, matching the LCD.
5. In MSG, leave the board alone (no key press): each message should auto-advance to the next on its own after a few seconds (per-message duration, see `hw/rtl/msg_duration_rom.v`) — this loops indefinitely, it does NOT go to sleep.
6. Return to HOME (`KEY0`) and wait about 60 seconds with no key press: system goes to SLEEP. LEDR[9] should blink at the moment it does.
7. Press any key in SLEEP: wake to IDLE.

---

## 10. Clean Shutdown (Avoid File-System Corruption)

When done:

1. In app terminal: press `Ctrl+C`.
2. Run:
   ```bash
   sync
   sudo poweroff
   ```
3. Wait for LEDs off.
4. Remove power.
5. Remove SD only if needed.

---

## 11. Linux Terminal Troubleshooting (Common Failures and Fixes)

If `ssh root@<BOARD_IP>` fails:

1. Check Ethernet cable and board power.
2. Reconfirm board IP from DHCP list.
3. Ping board from PC:
   ```bash
   ping <BOARD_IP>
   ```
4. If host-key mismatch error appears:
   ```bash
   ssh-keygen -R <BOARD_IP>
   ```

If `Permission denied` on SSH:

1. Confirm username is `root`.
2. Use correct board password.

If `make: command not found`:

1. Build tools are missing on Linux image.
2. Install `make` and `gcc` from package manager, then retry.

If `Makefile: ... missing separator`:

1. This is almost always CRLF line-ending corruption.
2. Run:
   ```bash
   cd /home/root/hps_app
   sed -i 's/\r$//' Makefile *.c *.h
   make clean
   make
   ```

If you see `ERROR: Cannot open /dev/mem`:

1. App is not running with enough privilege.
2. Run as root.

If you see `fsm_status read returned 0xFFFFFFFF`:

1. FPGA may not be programmed with correct `.sof`.
2. Reprogram in Quartus Programmer.
3. Reboot board and rerun app.

If LCD is stuck but 7-seg/buttons behave correctly:

This usually means the HPS app is reading the wrong LW-bridge offsets.

1. Verify the FPGA-side register map directly (these are known-good for this build):
   ```bash
   devmem 0xFF200150 32   # sysid (sanity check: should be non-zero)
   devmem 0xFF200140 32   # button_pio (raw buttons, active-low)
   devmem 0xFF200110 32   # fsm_status_pio
   devmem 0xFF200100 32   # timer_status_pio
   ```
2. Verify the HPS app uses the same LW offsets in `main.c`:
   - `BUTTON_PIO_BASE = 0x0140`
   - `FSM_STATUS_PIO_BASE = 0x0110`
   - `TIMER_STATUS_PIO_BASE = 0x0100`
3. Rebuild and run from the same folder:
   ```bash
   make clean
   make
   ./lcd_msg_app
   ```

If LCD stays blank:

1. Confirm app reached `=== LCD MESSAGE SYSTEM STARTED ===`.
2. Confirm `.sof` programming succeeded.
3. Confirm bridge mapping logs appear without error.
4. Reboot board and rerun after reprogramming FPGA.
