# DE10-Standard LCD Message System V2

This project implements an updated message display system for the Terasic DE10-Standard FPGA board. It migrates critical system control logic (button debouncing, edge detection, and idle timing) from the HPS software to the FPGA fabric for improved responsiveness and robustness.

## Project Architecture

The system uses a hybrid FPGA + HPS architecture:
*   **FPGA Logic**: Handles real-time tasks independently of the OS.
    *   **50ms Debouncer**: Filters button noise (Schmitt trigger synchronization + counter-based stability check).
    *   **Button Edge Detector**: Converts debounced button levels into single-cycle press pulses.
    *   **Idle Timer**: Maintains a 15-second inactivity timeout countdown.
    *   **UI FSM (Verilog)**: Implements INIT/IDLE/HOME/MSG/SLEEP states and message index navigation.
    *   **HEX Display Driver**: Outputs system status (Timer, Last Button, Timeout Flag) to onboard 7-segment displays.
*   **HPS Software**: Acts as LCD renderer and diagnostics client.
    *   Reads FPGA-exported FSM and timer status registers via LW Bridge.
    *   Renders LCD content based on hardware state and message index.
    *   Performs runtime sanity checks/warnings without owning control transitions.

### Hardware Components
*   `button_debouncer.v`: Parameterized debouncer module.
*   `button_edge_detector.v`: Rising-edge detector for one-pulse-per-press behavior.
*   `idle_timer.v`: Programmable countdown timer with enable/reset.
*   `message_fsm.v`: Verilog UI control FSM with timeout path and message index wrap-around.
*   `hex_display.v`: BCD-to-7-segment decoder.
*   `fpga_msg_controller.v`: Top-level wrapper integrating all FPGA modules.
*   `DE10_Standard_GHRD.v`: Top-level system instantiation connecting RTL to HPS via Qsys.

### Software Components
*   `main.c`: HPS LCD renderer that consumes FPGA status PIO registers (0x6000, 0x7000).
*   `Makefile`: Build script for cross-compilation or on-board compilation.

## Register Map

The HPS communicates with the FPGA via the Lightweight H2F Bridge (Base: 0xFF200000).

| PIO Name | Offset | Width | Direction | Description |
| :--- | :--- | :--- | :--- | :--- |
| `button_pio` | `0x5000` | 4-bit | Input | (Original) Raw button inputs. |
| `fsm_status_pio` | `0x6000` | 8-bit | Input | Bits [7:5]: **FSM State**. Bits [4:0]: **FSM Message Index**. |
| `timer_status_pio` | `0x7000` | 8-bit | Input | Bit [0]: **Timeout Flag** (1=Expired). Bits [4:1]: **Seconds Remaining** (BCD). |

## Simulation Verification (Pre-Hardware)

Run these from the project root before board testing.

1. Preflight simulator tools:
    ```powershell
    .\sim\check_sim_env.ps1
    ```

2. Run canonical simulation regression:
    ```powershell
    .\sim\run_all_sim.ps1
    ```

3. Optional: include legacy suites:
    ```powershell
    $env:RUN_LEGACY = "1"
    .\sim\run_all_sim.ps1
    ```

4. Full project verification (static checks + simulation gate):
    ```powershell
    $env:STRICT_SIM = "1"
    .\verify_all.ps1
    ```

5. Automated waveform analysis report (VCD checks + summary markdown):
    ```powershell
    .\sim\run_wave_analysis.ps1
    ```
    Report output:
    - `sim/results/wave_analysis_report.md`
    - Guide: `docs/waveform_analysis_guide.md`

6. Quartus 21.1 bundled Questa regression (canonical suites):
    ```powershell
    .\sim\run_quartus_questa_sim.ps1
    ```

7. Quartus-linked simulation collateral generation + Questa regression:
    ```powershell
    .\sim\run_quartus_questa_sim.ps1 -GenerateQuartusNetlist
    ```
    Generated Quartus simulation netlist:
    - `hw/quartus/sim/eda_questa/DE10_Standard_GHRD.vo`

8. One-command pre-board verification gate (canonical + legacy + waveform + Quartus netlist):
    ```powershell
    .\sim\run_pre_board_verification.ps1
    ```
    Summary report:
    - `sim/results/pre_board_verification_report.md`

If `iverilog` and `vvp` are installed but not in PATH, a temporary shell-only fix is:
```powershell
$env:Path = "C:\iverilog\bin;" + $env:Path
```

## Build Instructions

### 1. Build FPGA System (Windows)
We have provided an automated PowerShell script to fix Qsys and compile the design.
1.  Open PowerShell in the project root.
2.  Run:
    ```powershell
    .\hw\quartus\fix_then_build.ps1
    ```
    This script will:
    *   Validate or repair `soc_system.qsys` PIO connectivity as needed.
    *   Regenerate the HDL.
    *   Compile the Quartus project to generate `DE10_Standard_GHRD.sof`.

3.  Program the FPGA using Quartus Programmer.

### 2. Build HPS Software (Linux/Board)
1.  Copy `sw/hps_app` to the DE10 board.
2.  Compile the application:
    ```bash
    cd sw/hps_app
    make
    ```
3.  Run the application:
    ```bash
    ./lcd_msg_app
    ```

### 3. Build HPS Software (Windows via WSL cross-compile)
If you are on Windows, do **not** run `make` directly in PowerShell/CMD unless you have a full ARM-Linux cross toolchain installed.
The simplest supported path is WSL (Ubuntu) + `arm-linux-gnueabihf-gcc`.

1. Install toolchain inside WSL (run once):
    ```bash
    sudo apt-get update
    sudo apt-get install -y make gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf libc6-dev-armhf-cross
    ```

2. Build from Windows by invoking WSL:
    ```powershell
    wsl -d Ubuntu -- bash -lc "cd /mnt/c/Fpga_project_DE10_Standard_LCD_MSGS_-V2/sw/hps_app && make clean && make CC=arm-linux-gnueabihf-gcc"
    ```

3. The file you copy to the SD card is the single ARM-Linux executable:
    - `sw/hps_app/lcd_msg_app`

## Notes
*   If Qsys generation fails, refer to `hw/quartus/README_QSYS_FIX.txt` for manual repair instructions.
*   The `build_fpga.ps1` script is an alternative if you have already fixed Qsys manually.

## Hardware Validation (Presentation Sign-off)

To close hardware-only evidence items (for example, button-to-LCD end-to-end latency), use:

1. Runbook: `docs/board_validation_runbook.md`
2. Demo checklist: `docs/demo_dry_run_checklist.md`
2. Latency summary tool:
    ```powershell
    .\scripts\hardware\latency_summary.ps1 -CsvPath .\artifacts\hardware\latency_samples.csv -TargetMs 50
    ```
3. Sign-off report generator:
    ```powershell
    .\scripts\hardware\generate_signoff_report.ps1
    ```
4. One-command board sign-off runner:
    ```powershell
    .\scripts\hardware\run_board_signoff.ps1 -LatencyCsvPath .\artifacts\hardware\latency_samples.csv -LatencyTargetMs 50
    ```
5. Finalize parity matrix statuses when board evidence is complete:
    ```powershell
    .\scripts\hardware\finalize_signoff.ps1
    ```
6. Optional helpers for fast board logging:
    ```powershell
    .\scripts\hardware\reset_latency_samples.ps1
    .\scripts\hardware\append_latency_sample.ps1 -SampleId 1 -KeyId KEY1 -LatencyMs 31.2 -Tool scope -Confidence HIGH -Notes home_to_msg
    .\scripts\hardware\complete_demo_checklist.ps1 -Operator "name" -Board "DE10-Standard" -Bitstream "DE10_Standard_GHRD.sof" -HpsAppBuild "lcd_msg_app" -CompleteBoardItems
    ```
    Note: `append_latency_sample.ps1` removes seeded template rows automatically unless `-KeepTemplateRows` is specified.

The summary output can be attached directly to the parity matrix and final verification package.
